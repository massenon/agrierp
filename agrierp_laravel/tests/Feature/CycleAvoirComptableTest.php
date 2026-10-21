<?php

namespace Tests\Feature;

use App\Livewire\Ventes\RetoursAvoirs;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\CreditNote;
use App\Models\Customer;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\User;
use App\Services\FinancialReportService;
use App\Services\VatDeclarationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.27 (Sprint 14) — cycle RETOUR / AVOIR, jusqu'aux états financiers
 * et à la déclaration DGI.
 *
 * Dernier flux financier sans écriture. Le prototype l'exige explicitement à
 * l'étape 5 de son assistant : « ✅ Écriture comptable inverse · ✅ Mise à
 * jour CA et créances ». Seuls l'avoir et le mouvement de stock l'étaient.
 */
class CycleAvoirComptableTest extends TestCase
{
    use RefreshDatabase;

    private Sale $vente;

    private Product $produit;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-ventes', 'manage-ventes'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('caissier', 'web');
        $role->givePermissionTo(['view-ventes', 'manage-ventes']);

        $user = User::create([
            'name' => 'Caissière', 'email' => 'avoir@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'),
        ]);
        $user->assignRole($role);
        $this->actingAs($user);

        FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);

        foreach ([
            ['531', 'Caisse', 5],
            ['411', 'Clients', 4],
            ['443', 'TVA facturée', 4],
            ['701', 'Ventes de produits', 7],
        ] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }

        $categorie = ProductCategory::create(['label' => 'Œufs', 'is_active' => true]);

        $this->produit = Product::create([
            'sku' => 'OEUF-PLQ', 'name' => 'Plaquette d\'œufs', 'category_id' => $categorie->id,
            'unit' => 'plaquette', 'pricing_mode' => 'fourchette', 'price_min' => 2_000, 'price_max' => 6_000,
            'tva_rate' => 18, 'stock_qty' => 100, 'is_active' => true,
        ]);

        $client = Customer::create(['name' => 'GBAGUIDI Solange', 'phone' => '+22997333333', 'is_active' => true]);

        // Vente de 59 000 TTC (HT 50 000 + TVA 9 000), déjà comptabilisée.
        $this->vente = Sale::create([
            'customer_id' => $client->id,
            'payment_mode' => 'especes',
            'subtotal' => 59_000,
            'discount' => 0,
            'total' => 59_000,
            'delivery_fee' => 0,
            'status' => 'validee',
            'mecef_status' => 'transmise',
        ]);

        SaleLine::create([
            'sale_id' => $this->vente->id,
            'product_id' => $this->produit->id,
            'qty' => 10,
            'unit_price' => 5_900,
            'manual_total_amount' => 59_000,
        ]);

        app(\App\Actions\RecordSaleAccountingEntryAction::class)->execute($this->vente->fresh('lines'));
    }

    private function retourner(float $montant, string $decision = 'reintegre'): void
    {
        Livewire::test(RetoursAvoirs::class)
            ->set('saleId', $this->vente->id)
            ->set('productId', $this->produit->id)
            ->set('qty', 2)
            ->set('amount', $montant)
            ->set('reason', 'Produit détérioré')
            ->set('decision', $decision)
            ->call('saveReturn')
            ->assertHasNoErrors();
    }

    /**
     * L'ÉCRITURE INVERSE : sens des colonnes échangé par rapport à la vente.
     */
    public function test_a_credit_note_reverses_the_sale_entry(): void
    {
        $this->retourner(11_800);   // 2 plaquettes : HT 10 000 + TVA 1 800

        $avoir = CreditNote::firstOrFail();
        $this->assertNotNull($avoir->accounting_entry_id, "L'avoir doit generer son ecriture.");

        $ecriture = AccountingEntry::with('lines.account')->findOrFail($avoir->accounting_entry_id);
        $parCompte = $ecriture->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertEquals(10_000, (float) $parCompte['701']->debit, 'Le CA est DEBITE — inverse de la vente.');
        $this->assertEquals(1_800, (float) $parCompte['443']->debit, 'La TVA collectee est annulee a due concurrence.');
        $this->assertEquals(11_800, (float) $parCompte['411']->credit, 'Dette envers le client, jamais un decaissement.');
        $this->assertEquals($ecriture->total_debit, $ecriture->total_credit);
    }

    /**
     * ⚠️ LE POINT QUI DEMANDE UNE DÉCISION : la contrepartie reste 411 même
     * quand la vente d'origine a été payée en espèces. Un avoir constate une
     * dette, pas un remboursement — la caisse n'a pas bougé.
     */
    public function test_a_credit_note_never_moves_the_cash_account(): void
    {
        $this->retourner(11_800);

        $ecriture = AccountingEntry::with('lines.account')
            ->findOrFail(CreditNote::firstOrFail()->accounting_entry_id);

        $this->assertEquals('especes', $this->vente->payment_mode);
        $this->assertFalse(
            $ecriture->lines->contains(fn ($l) => $l->account->code === '531'),
            "Aucun mouvement de tresorerie : personne n'a encore ete rembourse."
        );
    }

    /** Le chiffre d'affaires baisse enfin du montant du retour. */
    public function test_the_return_reduces_the_revenue_in_the_income_statement(): void
    {
        $reports = app(FinancialReportService::class);
        $avant = $reports->compteResultat(now()->format('Y-m-d'));
        $this->assertEquals(50_000, $avant['ventes'], 'CA HT de la vente initiale.');

        $this->retourner(11_800);

        $apres = app(FinancialReportService::class)->compteResultat(now()->format('Y-m-d'));

        $this->assertEquals(40_000, $apres['ventes'], 'Le CA doit baisser du HT retourne.');
        $this->assertTrue($reports->bilan(now()->format('Y-m-d'))['is_balanced']);
        $this->assertTrue(
            $reports->balanceGenerale(now()->startOfYear()->format('Y-m-d'), now()->endOfYear()->format('Y-m-d'))['is_balanced']
        );
    }

    /**
     * 🔴→✅ LA DÉCLARATION DGI SURDÉCLARAIT LA TVA. `tvaCollectee()` ne lisait
     * que les ventes : l'entreprise aurait payé la taxe sur un CA annulé.
     */
    public function test_credit_notes_are_deducted_from_the_declared_vat(): void
    {
        $service = app(VatDeclarationService::class);
        $debut = now()->startOfMonth()->format('Y-m-d');
        $fin = now()->endOfMonth()->format('Y-m-d');

        $this->assertEquals(9_000, $service->tvaCollectee($debut, $fin)['total_tva']);

        $this->retourner(11_800);

        $collectee = $service->tvaCollectee($debut, $fin);

        $this->assertEquals(7_200, $collectee['total_tva'], '9 000 collectes moins 1 800 annules.');
        $this->assertEquals(40_000, $collectee['total_ht']);
        $this->assertCount(2, $collectee['rows'], "L'avoir figure en ligne propre, justifiable devant la DGI.");
        $this->assertEquals(7_200, $service->declaration($debut, $fin)['collectee']['total_tva'],
            'La declaration complete reprend bien la TVA nette des avoirs.');
    }

    /** L'avoir déduit porte bien son numéro et un montant négatif. */
    public function test_the_deducted_credit_note_appears_as_a_negative_line(): void
    {
        $this->retourner(11_800);

        $lignes = collect(app(VatDeclarationService::class)->tvaCollectee(
            now()->startOfMonth()->format('Y-m-d'), now()->endOfMonth()->format('Y-m-d')
        )['rows']);

        $ligneAvoir = $lignes->firstWhere('reference', CreditNote::firstOrFail()->credit_note_number);

        $this->assertNotNull($ligneAvoir, "L'avoir doit figurer sous son propre numero.");
        $this->assertEquals(-1_800, $ligneAvoir['tva']);
        $this->assertEquals(-11_800, $ligneAvoir['ttc']);
    }

    /** Un retour partiel ne rembourse que ce qui est réellement retenu. */
    public function test_a_partial_credit_note_only_reverses_its_own_amount(): void
    {
        $this->retourner(5_900);   // HT 5 000 + TVA 900

        $parCompte = AccountingEntry::with('lines.account')
            ->findOrFail(CreditNote::firstOrFail()->accounting_entry_id)
            ->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertEquals(5_000, (float) $parCompte['701']->debit);
        $this->assertEquals(900, (float) $parCompte['443']->debit);
        $this->assertEquals(45_000, app(FinancialReportService::class)->compteResultat(now()->format('Y-m-d'))['ventes']);
    }

    /** Réforme : pas de retour en stock, mais l'avoir reste comptabilisé. */
    public function test_a_written_off_return_is_still_posted_but_never_restocked(): void
    {
        $stockAvant = (float) $this->produit->fresh()->stock_qty;

        $this->retourner(11_800, 'reforme');

        $this->assertEquals($stockAvant, (float) $this->produit->fresh()->stock_qty, 'Produit reforme : aucun retour en stock.');
        $this->assertNotNull(CreditNote::firstOrFail()->accounting_entry_id, "L'avoir est du au client meme si le produit est perdu.");
    }

    /** Réintégré : le stock remonte ET l'écriture existe. */
    public function test_a_restocked_return_moves_both_stock_and_ledger(): void
    {
        $stockAvant = (float) $this->produit->fresh()->stock_qty;

        $this->retourner(11_800);

        $this->assertEquals($stockAvant + 2, (float) $this->produit->fresh()->stock_qty);
        $this->assertEquals(1, AccountingEntry::where('source_type', 'credit_note')->count());
    }

    public function test_a_credit_note_is_never_posted_twice(): void
    {
        $this->retourner(11_800);

        app(\App\Actions\RecordCreditNoteAccountingEntryAction::class)
            ->execute(CreditNote::firstOrFail()->load('product'));

        $this->assertEquals(1, AccountingEntry::where('source_type', 'credit_note')->count());
    }

    /**
     * 🔴→✅ GARDE RBAC ABSENTE. La route du hub ne porte que `can:view-ventes`
     * et ni `saveReturn()` ni `markAsTreated()` n'appelaient `authorize()` :
     * un profil en lecture seule créait des avoirs et réintégrait du stock.
     */
    public function test_a_read_only_user_can_neither_create_nor_settle_a_credit_note(): void
    {
        $lecteur = User::create([
            'name' => 'Observateur', 'email' => 'lecture-ventes@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'),
        ]);
        $lectureSeule = Role::findOrCreate('observateur', 'web');
        $lectureSeule->givePermissionTo('view-ventes');
        $lecteur->assignRole($lectureSeule);

        $this->actingAs($lecteur);

        Livewire::test(RetoursAvoirs::class)
            ->set('saleId', $this->vente->id)
            ->set('productId', $this->produit->id)
            ->set('qty', 2)->set('amount', 11_800)
            ->set('reason', 'Tentative sans droit')
            ->call('saveReturn')
            ->assertForbidden();

        $this->assertEquals(0, CreditNote::count());
        $this->assertEquals(100, (float) $this->produit->fresh()->stock_qty, 'Aucun stock reintegre sans autorisation.');

        $avoir = CreditNote::create([
            'credit_note_number' => CreditNote::generateCreditNoteNumber(),
            'sale_id' => $this->vente->id, 'product_id' => $this->produit->id,
            'qty' => 1, 'amount' => 5_900, 'reason' => 'Existant', 'decision' => 'reforme', 'status' => 'en_attente',
        ]);

        Livewire::test(RetoursAvoirs::class)->call('markAsTreated', $avoir->id)->assertForbidden();

        $this->assertEquals('en_attente', $avoir->fresh()->status);
    }
}
