<?php

namespace Tests\Feature;

use App\Livewire\Achats\BonsCommande;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Payable;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseLine;
use App\Models\PurchaseOrder;
use App\Models\PurchaseOrderLine;
use App\Models\Role;
use App\Models\StockMovement;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\PurchaseReturnService;
use App\Services\SupplierSettlementService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.21 (B) — LA RÉCEPTION D'UN BON DE COMMANDE PASSE SON ÉCRITURE.
 *
 * `BonsCommande::confirmReceiveOrder` créait l'achat, ses lignes, le stock et une dette (`Payable`) SANS AUCUNE
 * écriture comptable : dette sans contrepartie en 401, charge 601 jamais constatée, règlement ultérieur = Débit 401
 * sans Crédit correspondant. C'est la règle n°1 du projet (toute opération financière produit son écriture).
 *
 * Désormais la réception passe par `RecordPurchaseAction` — la MÊME comptabilisation que l'achat direct
 * (tickets 14.24 / 14.78) : datée du jour de la RÉCEPTION, une seule écriture, dans la transaction du stock et de
 * la dette. Aucun achat déjà reçu n'est régularisé (décision cabinet) : `comptabilite:achats-sans-ecriture` les liste.
 */
class ReceptionBonCommandeComptableTest extends TestCase
{
    use RefreshDatabase;

    private User $acheteur;

    private Supplier $fournisseur;

    private Product $aliment;

    private TreasuryAccount $caisse;

    private FiscalYear $exercice;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-achats', 'manage-achats'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('acheteur', 'web')->givePermissionTo(['view-achats', 'manage-achats']);
        Role::findOrCreate('lecteur', 'web')->givePermissionTo(['view-achats']);

        $this->acheteur = $this->utilisateur('acheteur');

        $this->fournisseur = Supplier::create(['name' => 'Provenderie du Plateau', 'category' => 'Aliments', 'is_active' => true]);

        $this->aliment = Product::create([
            'sku' => 'ALI-PONTE-25', 'name' => 'Aliment ponte 25kg',
            'category_id' => ProductCategory::create(['label' => 'Aliments', 'is_active' => true])->id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'price_min' => 5900, 'price_max' => 5900,
            'tva_rate' => 18, 'stock_qty' => 5, 'is_active' => true,
        ]);

        $this->caisse = TreasuryAccount::create([
            'label' => 'Caisse Physique', 'account_code' => '531', 'type' => 'caisse', 'balance' => 100_000, 'is_active' => true,
        ]);

        $this->exercice = FiscalYear::create([
            'year' => (int) now()->format('Y'),
            'start_date' => now()->startOfYear()->toDateString(),
            'end_date' => now()->endOfYear()->toDateString(),
            'status' => 'ouvert',
        ]);

        foreach ([['601', 'Achats', 6], ['401', 'Fournisseurs', 4], ['409', 'Fournisseurs débiteurs', 4], ['445', 'TVA récupérable', 4], ['531', 'Caisse', 5]] as [$code, $libelle, $classe]) {
            ChartOfAccount::firstOrCreate(['code' => $code], ['label' => $libelle, 'class' => $classe, 'is_active' => true]);
        }
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function utilisateur(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    /** Bon de commande : 10 sacs à 5 900 FCFA TTC = 59 000 (HT 50 000, TVA 9 000). */
    private function bon(): PurchaseOrder
    {
        $bon = PurchaseOrder::create(['supplier_id' => $this->fournisseur->id, 'status' => 'envoye']);
        PurchaseOrderLine::create([
            'purchase_order_id' => $bon->id, 'product_id' => $this->aliment->id, 'qty' => 10, 'estimated_unit_price' => 5900,
        ]);

        return $bon;
    }

    private function recevoir(PurchaseOrder $bon, ?User $u = null)
    {
        return Livewire::actingAs($u ?? $this->acheteur)->test(BonsCommande::class)
            ->set('receivingOrderId', $bon->id)
            ->call('confirmReceiveOrder');
    }

    private function net(string $code): float
    {
        $l = DB::selectOne(
            'select coalesce(sum(l.debit),0) - coalesce(sum(l.credit),0) as net
             from accounting_entry_lines l join chart_of_accounts c on c.id = l.account_id where c.code = ?',
            [$code]
        );

        return round((float) $l->net, 2);
    }

    private function assertLesDeuxLivresConcordent(): void
    {
        $comptes = round((float) DB::table('treasury_accounts')->sum('balance'), 2);
        $l = DB::selectOne(
            'select coalesce(sum(l.debit),0) - coalesce(sum(l.credit),0) as net
             from accounting_entry_lines l join chart_of_accounts c on c.id = l.account_id where c.class = 5'
        );
        // La caisse de départ (100 000) a été posée directement dans la table : on compare les VARIATIONS.
        $this->assertEquals($comptes - 100_000, round((float) $l->net, 2), 'Les deux livres de trésorerie divergent.');
    }

    // ------------------------------------------------------------------ B1 : la réception passe son écriture

    public function test_la_reception_passe_une_ecriture_equilibree_datee_du_jour_de_reception(): void
    {
        // Le bon est passé 10 jours avant sa réception : l'écriture porte la date de RÉCEPTION, pas celle du bon.
        $reception = now()->startOfMonth()->addDays(2)->setTime(9, 0);
        $creation = $reception->copy()->subDays(10);
        Carbon::setTestNow($creation);
        $bon = $this->bon();

        Carbon::setTestNow($reception);

        $this->recevoir($bon)->assertHasNoErrors();

        $achat = Purchase::where('purchase_order_id', $bon->id)->firstOrFail();
        $this->assertNotSame($creation->toDateString(), $reception->toDateString());
        $this->assertSame($reception->toDateString(), $achat->purchase_date->toDateString());
        $this->assertNotNull($achat->accounting_entry_id, "La réception d'un bon de commande doit passer son écriture.");
        $this->assertSame('recu', $bon->fresh()->status);

        $ecriture = AccountingEntry::with('lines.account')->findOrFail($achat->accounting_entry_id);
        $this->assertSame($reception->toDateString(), $ecriture->entry_date->toDateString());
        $this->assertSame('purchase', $ecriture->source_type);
        $this->assertSame($achat->id, $ecriture->source_id);

        $parCompte = $ecriture->lines->keyBy(fn ($l) => $l->account->code);
        $this->assertCount(3, $ecriture->lines);
        $this->assertEquals(50_000, (float) $parCompte['601']->debit);
        $this->assertEquals(9_000, (float) $parCompte['445']->debit);
        $this->assertEquals(59_000, (float) $parCompte['401']->credit, 'Toute la dette en 401 : aucun règlement à la réception.');
        $this->assertEquals(
            round($ecriture->lines->sum('debit'), 2),
            round($ecriture->lines->sum('credit'), 2)
        );
        $this->assertMatchesRegularExpression('/^OD-\d{4}-0001 — /', $ecriture->reference);

        // Recalcul indépendant par somme SQL : 601 débiteur de 50 000, 401 créditeur de 59 000.
        $this->assertSame(50_000.0, $this->net('601'));
        $this->assertSame(-59_000.0, $this->net('401'));
        $this->assertSame(9_000.0, $this->net('445'));

        // Les autres effets sont intacts : stock, mouvement, ligne, dette ouverte.
        $this->assertEquals(15, (float) $this->aliment->fresh()->stock_qty);
        $this->assertSame(1, StockMovement::where('reference_type', 'purchase')->where('reference_id', $achat->id)->count());
        $this->assertSame(1, PurchaseLine::where('purchase_id', $achat->id)->count());
        $dette = Payable::where('purchase_id', $achat->id)->firstOrFail();
        $this->assertEquals(59_000, (float) $dette->amount);
        $this->assertEquals(0, (float) $dette->amount_paid);
        $this->assertSame('credit', $achat->payment_mode);

        // Aucun mouvement de trésorerie à la réception.
        $this->assertEquals(100_000, (float) $this->caisse->fresh()->balance);
        $this->assertLesDeuxLivresConcordent();
    }

    public function test_une_reception_rejouee_ne_double_rien(): void
    {
        $bon = $this->bon();

        $this->recevoir($bon);
        $this->recevoir($bon);     // second écran / double clic

        $this->assertSame(1, Purchase::where('purchase_order_id', $bon->id)->count());
        $this->assertSame(1, AccountingEntry::count());
        $this->assertSame(1, Payable::count());
        $this->assertEquals(15, (float) $this->aliment->fresh()->stock_qty);
        $this->assertSame(50_000.0, $this->net('601'));
    }

    // ------------------------------------------------------------------ B2 : échec propre, aucun résidu

    private function assertAucunResidu(PurchaseOrder $bon): void
    {
        $this->assertSame(0, Purchase::count(), 'Aucun achat ne doit subsister.');
        $this->assertSame(0, PurchaseLine::count());
        $this->assertSame(0, Payable::count(), 'Aucune dette orpheline.');
        $this->assertSame(0, AccountingEntry::count());
        $this->assertSame(0, StockMovement::count());
        $this->assertEquals(5, (float) $this->aliment->fresh()->stock_qty, 'Le stock ne doit pas bouger.');
        $this->assertSame('envoye', $bon->fresh()->status, 'Le bon reste à recevoir.');
    }

    public function test_exercice_clos_refuse_proprement_sans_residu(): void
    {
        $bon = $this->bon();
        $this->exercice->update(['status' => 'cloture']);

        $this->recevoir($bon)->assertDispatched('toast', type: 'error');

        $this->assertAucunResidu($bon);
    }

    public function test_exercice_absent_refuse_proprement_sans_residu(): void
    {
        $bon = $this->bon();
        $this->exercice->delete();

        $this->recevoir($bon)->assertDispatched('toast', type: 'error');

        $this->assertAucunResidu($bon);
    }

    public function test_compte_de_dette_absent_du_plan_refuse_sans_residu(): void
    {
        $bon = $this->bon();
        ChartOfAccount::where('code', '401')->delete();

        $this->recevoir($bon)->assertDispatched('toast', type: 'error');

        $this->assertAucunResidu($bon);
    }

    public function test_la_reception_exige_le_droit_manage_achats(): void
    {
        $bon = $this->bon();
        $this->utilisateur('lecteur');

        $this->recevoir($bon, User::where('username', 'lecteur')->first())->assertForbidden();

        $this->assertAucunResidu($bon);
    }

    // ------------------------------------------------------------------ B3 : de bout en bout

    public function test_bon_de_commande_reception_reglement_puis_retour_fournisseur(): void
    {
        $bon = $this->bon();
        $this->recevoir($bon);
        $achat = Purchase::where('purchase_order_id', $bon->id)->firstOrFail();

        // Règlement partiel de 20 000 : Débit 401 / Crédit 531 — la dette de 401 existe, le règlement a sa contrepartie.
        app(SupplierSettlementService::class)->regler($this->fournisseur->id, 20_000, $this->caisse->id);
        $this->assertSame(-39_000.0, $this->net('401'), '401 : 59 000 dus - 20 000 réglés.');
        $this->assertEquals(80_000, (float) $this->caisse->fresh()->balance);
        $this->assertLesDeuxLivresConcordent();

        // Retour fournisseur : AUTORISÉ (l'achat a son écriture d'origine, contrairement à avant ce ticket).
        $lignes = app(PurchaseReturnService::class)->annuler($achat, 'Sacs éventrés à la livraison');
        $this->assertCount(1, $lignes);

        // Contre-passation : 601 et 445 soldés, dette annulée (401 = 0), part payée devenue créance 409.
        $this->assertSame(0.0, $this->net('601'));
        $this->assertSame(0.0, $this->net('445'));
        $this->assertSame(0.0, $this->net('401'));
        $this->assertSame(20_000.0, $this->net('409'));
        $this->assertEquals(20_000, (float) $achat->fresh()->supplier_credit);
        $this->assertNotNull($achat->fresh()->returned_at);
        $this->assertEquals(5, (float) $this->aliment->fresh()->stock_qty, 'Stock revenu à sa valeur initiale.');

        // Chaque écriture est équilibrée et les numéros se suivent (réception, règlement, retour).
        foreach (AccountingEntry::with('lines')->get() as $e) {
            $this->assertEquals(round($e->lines->sum('debit'), 2), round($e->lines->sum('credit'), 2));
        }
        $this->assertSame(3, AccountingEntry::count());
        $numeros = AccountingEntry::orderBy('created_at')->get()->map(fn ($e) => substr($e->reference, 0, 12))->sort()->values()->all();
        $this->assertCount(3, array_unique($numeros));

        $this->assertLesDeuxLivresConcordent();
    }

    public function test_effet_sur_les_retours_ancien_achat_refuse_nouvel_achat_retournable(): void
    {
        // Achat reçu AVANT le correctif : pas d'écriture (simulé par insertion directe) -> retour refusé (15.20).
        $ancien = Purchase::create([
            'supplier_id' => $this->fournisseur->id, 'payment_mode' => 'credit', 'total' => 59_000,
            'purchase_date' => now()->toDateString(),
        ]);
        PurchaseLine::create(['purchase_id' => $ancien->id, 'product_id' => $this->aliment->id, 'qty' => 10, 'unit_price' => 5900]);
        $this->aliment->update(['stock_qty' => 15]);

        try {
            app(PurchaseReturnService::class)->annuler($ancien, 'Erreur');
            $this->fail('Le retour d\'un achat sans écriture doit rester refusé.');
        } catch (ValidationException $e) {
            $this->assertStringContainsString('écriture', collect($e->errors())->flatten()->implode(' '));
        }

        // Achat reçu APRÈS le correctif : retournable.
        $bon = $this->bon();
        $this->recevoir($bon);
        $nouveau = Purchase::where('purchase_order_id', $bon->id)->firstOrFail();

        $this->assertCount(1, app(PurchaseReturnService::class)->annuler($nouveau, 'Erreur'));
    }

    // ------------------------------------------------------------------ B4 : détection des achats sans écriture

    public function test_commande_achats_sans_ecriture_liste_sans_rien_modifier(): void
    {
        $ancien1 = Purchase::create([
            'supplier_id' => $this->fournisseur->id, 'payment_mode' => 'credit', 'total' => 405_000,
            'purchase_date' => '2026-03-02',
        ]);
        $ancien2 = Purchase::create([
            'supplier_id' => $this->fournisseur->id, 'payment_mode' => 'credit', 'total' => 12_500,
            'purchase_date' => '2026-04-11',
        ]);

        // Un achat reçu après le correctif a son écriture : il n'est PAS listé.
        $bon = $this->bon();
        $this->recevoir($bon);
        $recent = Purchase::where('purchase_order_id', $bon->id)->firstOrFail();

        $avant = [Purchase::count(), AccountingEntry::count(), DB::table('purchases')->whereNull('accounting_entry_id')->count()];

        $this->artisan('comptabilite:achats-sans-ecriture')
            ->expectsOutputToContain($ancien1->id.'  2026-03-02  405000.00 FCFA')
            ->expectsOutputToContain($ancien2->id.'  2026-04-11  12500.00 FCFA')
            ->expectsOutputToContain('2 achat(s) sans écriture comptable')
            ->doesntExpectOutputToContain($recent->id)
            ->assertExitCode(1);

        $this->assertSame($avant, [Purchase::count(), AccountingEntry::count(), DB::table('purchases')->whereNull('accounting_entry_id')->count()]);
        $this->assertNull($ancien1->fresh()->accounting_entry_id, 'La commande ne régularise rien.');
    }

    public function test_commande_achats_sans_ecriture_muette_quand_tout_est_comptabilise(): void
    {
        $this->recevoir($this->bon());

        $this->artisan('comptabilite:achats-sans-ecriture')
            ->expectsOutputToContain('Aucun achat sans écriture comptable')
            ->assertExitCode(0);
    }

    // ------------------------------------------------------------------ garde-fou source

    public function test_la_page_ne_cree_plus_d_achat_elle_meme(): void
    {
        $source = file_get_contents(app_path('Livewire/Achats/BonsCommande.php'));

        $this->assertStringContainsString('RecordPurchaseAction', $source);
        $this->assertStringNotContainsString('Purchase::create', $source, 'La réception doit passer par RecordPurchaseAction (une seule comptabilisation des achats).');
        $this->assertStringNotContainsString('Payable::create', $source);
    }
}
