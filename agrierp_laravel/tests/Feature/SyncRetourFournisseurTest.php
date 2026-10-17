<?php

namespace Tests\Feature;

use App\Actions\RecordPurchaseAction;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Payable;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseReturn;
use App\Models\Role;
use App\Models\StockMovement;
use App\Models\Supplier;
use App\Models\SupplierRefund;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\SupplierSettlementService;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket 15.20 — RETOUR FOURNISSEUR ET REMBOURSEMENT FOURNISSEUR ENVOYÉS PAR UN POSTE
 * (`purchase_returns`, `supplier_refunds`).
 *
 * ⚠️⚠️ CE QUE CES TESTS PROTÈGENT. Un retour est l'ANNULATION COMPLÈTE d'un achat (D6) et porte CINQ effets, que le poste
 * n'applique JAMAIS : lignes de retour, stock décrémenté (jamais négatif), part non payée de la dette annulée,
 * contre-passation de l'écriture d'achat (D7), part déjà payée = créance sur le fournisseur (compte 409). Un remboursement
 * (D8) entre en trésorerie ET au journal (Débit trésorerie / Crédit 409), plafonné à la créance ouverte.
 *
 * ⚠️ Chaque chiffre comptable est RECALCULÉ INDÉPENDAMMENT (somme SQL brute des lignes d'écriture par compte, jamais
 * relue depuis le service) et comparé : un retour dont seules les valeurs changent ne lève aucune erreur.
 */
class SyncRetourFournisseurTest extends TestCase
{
    use RefreshDatabase;

    private User $acheteur;

    private User $caissier;

    private Supplier $fournisseur;

    private Product $aliment;

    private Product $medicament;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-achats', 'web');
        Role::findOrCreate('acheteur', 'web')->givePermissionTo('manage-achats');
        Role::findOrCreate('caissier', 'web');

        $this->acheteur = $this->utilisateur('acheteur');
        $this->caissier = $this->utilisateur('caissier');

        $this->fournisseur = Supplier::create(['name' => 'Provenderie du Plateau', 'category' => 'Aliments', 'is_active' => true]);

        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);

        $this->aliment = $this->produit($categorie, 'ALI-PONTE-25', 'Aliment ponte 25kg', 5);
        $this->medicament = $this->produit($categorie, 'MED-VIT-01', 'Vitamines', 2);

        // Solde de départ 0 : les DEUX livres (solde du compte, grand livre de classe 5) partent du même point.
        $this->caisse = TreasuryAccount::create([
            'label' => 'Caisse Physique', 'account_code' => '531',
            'type' => 'caisse', 'balance' => 0, 'is_active' => true,
        ]);

        FiscalYear::create([
            'year' => (int) now()->format('Y'),
            'start_date' => now()->startOfYear()->toDateString(),
            'end_date' => now()->endOfYear()->toDateString(),
            'status' => 'ouvert',
        ]);

        foreach ([['601', "Achats d'aliments", 6], ['401', 'Fournisseurs', 4], ['409', 'Fournisseurs débiteurs', 4], ['531', 'Caisse', 5]] as [$code, $libelle, $classe]) {
            ChartOfAccount::firstOrCreate(['code' => $code], ['label' => $libelle, 'class' => $classe, 'is_active' => true]);
        }
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

    private function produit(ProductCategory $categorie, string $sku, string $nom, float $stock): Product
    {
        return Product::create([
            'sku' => $sku, 'name' => $nom, 'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'price_min' => 8000, 'price_max' => 8000,
            'stock_qty' => $stock, 'is_active' => true,
        ]);
    }

    /**
     * Achat de 100 000 FCFA en deux lignes (10 aliments à 5 000 + 4 vitamines à 12 500), tel que le web et le poste
     * l'enregistrent : par `RecordPurchaseAction` (stock, trésorerie, dette, écriture).
     */
    private function acheter(float $regle, ?string $date = null): Purchase
    {
        return app(RecordPurchaseAction::class)->execute(
            $this->fournisseur->id,
            [
                ['product_id' => $this->aliment->id, 'qty' => 10, 'unit_price' => 5000],
                ['product_id' => $this->medicament->id, 'qty' => 4, 'unit_price' => 12500],
            ],
            $regle >= 100000 ? 'especes' : ($regle > 0 ? 'especes' : 'credit'),
            $this->caisse->id,
            $regle,
            (string) Str::uuid(),
            $date,
        );
    }

    /** @return array<string, mixed> */
    private function retour(Purchase $achat, array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'purchase_id' => $achat->id,
            'reason' => 'Marchandises endommagées / périmées',
            'return_date' => now()->toDateString(),
        ], $remplace);
    }

    /** @return array<string, mixed> */
    private function remboursement(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'supplier_id' => $this->fournisseur->id,
            'treasury_account_id' => $this->caisse->id,
            'amount' => 60000,
            'refund_date' => now()->toDateString(),
        ], $remplace);
    }

    private function pousser(User $u, array $corps): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test'] + $corps)->assertOk();
    }

    /** Solde net (débit - crédit) d'un compte, recalculé en SQL brut. */
    private function net(string $code): float
    {
        $ligne = DB::selectOne(
            'select coalesce(sum(l.debit),0) - coalesce(sum(l.credit),0) as net
             from accounting_entry_lines l join chart_of_accounts c on c.id = l.account_id where c.code = ?',
            [$code]
        );

        return round((float) $ligne->net, 2);
    }

    /** @return array{0: float, 1: float} [Σ soldes des comptes de trésorerie, Σ (débit - crédit) de la classe 5] */
    private function livresDeTresorerie(): array
    {
        $comptes = round((float) DB::table('treasury_accounts')->sum('balance'), 2);
        $ligne = DB::selectOne(
            'select coalesce(sum(l.debit),0) - coalesce(sum(l.credit),0) as net
             from accounting_entry_lines l join chart_of_accounts c on c.id = l.account_id where c.class = 5'
        );

        return [$comptes, round((float) $ligne->net, 2)];
    }

    private function assertLesDeuxLivresConcordent(): void
    {
        [$comptes, $grandLivre] = $this->livresDeTresorerie();
        $this->assertEquals($comptes, $grandLivre, 'Les deux livres de trésorerie divergent.');
    }

    // ------------------------------------------------------------------
    // Retour : les trois formes d'achat
    // ------------------------------------------------------------------

    public function test_le_retour_d_un_achat_paye_contre_passe_et_ouvre_une_creance_409(): void
    {
        $achat = $this->acheter(100000);
        $this->assertEquals(100000, -$this->net('531'), 'préalable : 100 000 sortis de la caisse');

        $ecrituresAvant = AccountingEntry::count();
        $r = $this->retour($achat);
        $rep = $this->pousser($this->acheteur, ['purchase_returns' => [$r]]);

        $this->assertSame([$r['id']], $rep->json('purchase_returns.accepted'));
        $this->assertSame([], $rep->json('purchase_returns.rejected'));

        // Stock : revenu à l'état d'avant l'achat (5 et 2), par deux mouvements `purchase_return`.
        $this->assertEquals(5, $this->aliment->fresh()->stock_qty);
        $this->assertEquals(2, $this->medicament->fresh()->stock_qty);
        $this->assertSame(2, PurchaseReturn::where('purchase_id', $achat->id)->count());
        $this->assertSame(2, StockMovement::where('reference_type', 'purchase_return')->where('type', 'sortie')->count());

        // Journal, recalculé indépendamment : 601 soldé, 401 intact (jamais touché), 409 débité de 100 000.
        $this->assertSame($ecrituresAvant + 1, AccountingEntry::count());
        $this->assertEquals(0, $this->net('601'));
        $this->assertEquals(0, $this->net('401'));
        $this->assertEquals(100000, $this->net('409'));

        // Trésorerie : le retour ne ramène AUCUN argent en caisse (c'est le remboursement qui le fera).
        $this->assertEquals(-100000, $this->caisse->fresh()->balance);
        $this->assertLesDeuxLivresConcordent();

        $achat = $achat->fresh();
        $this->assertNotNull($achat->returned_at);
        $this->assertEquals(100000, $achat->supplier_credit);
    }

    public function test_le_retour_d_un_achat_a_credit_annule_la_dette_et_ne_cree_aucune_creance(): void
    {
        $achat = $this->acheter(0);
        $this->assertEquals(100000, Payable::where('purchase_id', $achat->id)->first()->balance);
        $this->assertEquals(-100000, $this->net('401'), 'préalable : 100 000 dus au fournisseur');

        $r = $this->retour($achat);
        $rep = $this->pousser($this->acheteur, ['purchase_returns' => [$r]]);

        $this->assertSame([$r['id']], $rep->json('purchase_returns.accepted'));

        // La dette est annulée, pas seulement masquée.
        $dette = Payable::where('purchase_id', $achat->id)->first();
        $this->assertSame('soldee', $dette->status);
        $this->assertEquals(0, $dette->balance);
        $this->assertSame(0, Payable::whereColumn('amount_paid', '<', 'amount')->count());

        // Journal : 401 et 601 soldés, AUCUNE ligne 409, aucune trésorerie.
        $this->assertEquals(0, $this->net('401'));
        $this->assertEquals(0, $this->net('601'));
        $this->assertEquals(0, $this->net('409'));
        $this->assertEquals(0, $this->net('531'));
        $this->assertEquals(0, $achat->fresh()->supplier_credit);
        $this->assertLesDeuxLivresConcordent();
    }

    public function test_le_retour_d_un_achat_partiellement_paye_partage_dette_et_creance(): void
    {
        $achat = $this->acheter(40000);
        $this->assertEquals(60000, Payable::where('purchase_id', $achat->id)->first()->balance);

        $r = $this->retour($achat);
        $this->pousser($this->acheteur, ['purchase_returns' => [$r]]);

        // 60 000 non payés : dette annulée (401 soldé). 40 000 déjà payés : créance 409. 601 soldé.
        $this->assertEquals(0, $this->net('401'));
        $this->assertEquals(40000, $this->net('409'));
        $this->assertEquals(0, $this->net('601'));
        $this->assertEquals(40000, $achat->fresh()->supplier_credit);

        $dette = Payable::where('purchase_id', $achat->id)->first();
        $this->assertSame('soldee', $dette->status);
        // La part déjà payée reste inscrite sur la dette (40 000), la part annulée a disparu.
        $this->assertEquals(40000, $dette->amount);
        $this->assertEquals(40000, $dette->amount_paid);

        // Écriture de retour : exactement trois lignes non nulles, équilibrée, datée du jour du retour.
        $ecriture = AccountingEntry::where('source_type', 'purchase_return')->firstOrFail();
        $this->assertCount(3, $ecriture->lines);
        $this->assertEquals(100000, $ecriture->lines->sum('credit'));
        $this->assertEquals(100000, $ecriture->lines->sum('debit'));
        $this->assertSame(0, $ecriture->lines->filter(fn ($l) => (float) $l->debit == 0 && (float) $l->credit == 0)->count());
        $this->assertLesDeuxLivresConcordent();
    }

    public function test_un_reglement_ulterieur_de_la_dette_agrandit_la_creance_au_retour(): void
    {
        $achat = $this->acheter(40000);
        // 20 000 payés ensuite au fournisseur (FIFO, service 15.16) : la dette de l'achat passe à 40 000.
        app(SupplierSettlementService::class)->regler($this->fournisseur->id, 20000, $this->caisse->id);
        $this->assertEquals(40000, Payable::where('purchase_id', $achat->id)->first()->balance);

        $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);

        // Non payé = 40 000 (D 401) ; déjà payé = 100 000 - 40 000 = 60 000 (D 409).
        $this->assertEquals(0, $this->net('401'));
        $this->assertEquals(60000, $this->net('409'));
        $this->assertEquals(60000, $achat->fresh()->supplier_credit);
        $this->assertLesDeuxLivresConcordent();
    }

    public function test_la_tva_recuperable_de_l_achat_est_contre_passee_au_montant_exact_de_l_origine(): void
    {
        \App\Services\TvaSettingService::oublier();
        ChartOfAccount::firstOrCreate(['code' => '445'], ['label' => 'TVA récupérable', 'class' => 4, 'is_active' => true]);
        $this->aliment->update(['tva_rate' => 18]);

        $achat = app(RecordPurchaseAction::class)->execute(
            $this->fournisseur->id,
            [['product_id' => $this->aliment->id, 'qty' => 10, 'unit_price' => 11800]],
            'especes', $this->caisse->id, 118000, (string) Str::uuid(),
        );
        // Préalable, recalculé : 118 000 TTC = 100 000 HT (601) + 18 000 de TVA (445).
        $this->assertEquals(100000, $this->net('601'));
        $this->assertEquals(18000, $this->net('445'));

        $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);

        $this->assertEquals(0, $this->net('601'));
        $this->assertEquals(0, $this->net('445'));
        $this->assertEquals(118000, $this->net('409'));
        $this->assertEquals(118000, $achat->fresh()->supplier_credit);
        $this->assertLesDeuxLivresConcordent();
    }

    public function test_l_ecriture_d_origine_n_est_jamais_modifiee_et_la_contre_passation_est_datee_du_retour(): void
    {
        $achat = $this->acheter(100000, now()->subDays(5)->toDateString());
        $origine = AccountingEntry::findOrFail($achat->accounting_entry_id);
        $empreinte = [$origine->entry_date->toDateString(), $origine->reference, $origine->lines->map(fn ($l) => [$l->account_id, (string) $l->debit, (string) $l->credit])->all()];

        $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);

        $origine = AccountingEntry::findOrFail($achat->accounting_entry_id);
        $this->assertSame($empreinte, [$origine->entry_date->toDateString(), $origine->reference, $origine->lines->map(fn ($l) => [$l->account_id, (string) $l->debit, (string) $l->credit])->all()]);

        $contre = AccountingEntry::where('source_type', 'purchase_return')->firstOrFail();
        $this->assertSame(now()->toDateString(), $contre->entry_date->toDateString(), 'datée du jour du RETOUR');
        $this->assertNotSame($origine->reference, $contre->reference);
        $this->assertStringContainsString('Retour fournisseur', $contre->reference);
    }

    // ------------------------------------------------------------------
    // Idempotence, double retour, renvoi
    // ------------------------------------------------------------------

    public function test_un_renvoi_du_meme_retour_est_acquitte_sans_rien_rejouer(): void
    {
        $achat = $this->acheter(100000);
        $r = $this->retour($achat);

        $this->pousser($this->acheteur, ['purchase_returns' => [$r]]);
        $stock = $this->aliment->fresh()->stock_qty;
        $ecritures = AccountingEntry::count();
        $mouvements = StockMovement::count();

        $rep = $this->pousser($this->acheteur, ['purchase_returns' => [$r]]);

        $this->assertSame([$r['id']], $rep->json('purchase_returns.accepted'));
        $this->assertSame([], $rep->json('purchase_returns.rejected'));
        $this->assertEquals($stock, $this->aliment->fresh()->stock_qty, 'pas de second décrément');
        $this->assertSame($ecritures, AccountingEntry::count());
        $this->assertSame($mouvements, StockMovement::count());
        $this->assertSame(2, PurchaseReturn::count());
    }

    public function test_un_renvoi_acquitte_le_reste_meme_apres_la_cloture_de_l_exercice(): void
    {
        $achat = $this->acheter(100000);
        $r = $this->retour($achat);
        $this->pousser($this->acheteur, ['purchase_returns' => [$r]]);

        FiscalYear::query()->update(['status' => 'cloture']);

        $rep = $this->pousser($this->acheteur, ['purchase_returns' => [$r]]);

        $this->assertSame([$r['id']], $rep->json('purchase_returns.accepted'));
    }

    public function test_un_second_retour_du_meme_achat_sous_un_autre_id_est_refuse_avec_son_motif(): void
    {
        $achat = $this->acheter(100000);
        $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);

        $stock = $this->aliment->fresh()->stock_qty;
        $autre = $this->retour($achat);
        $rep = $this->pousser($this->acheteur, ['purchase_returns' => [$autre]]);

        $this->assertSame([], $rep->json('purchase_returns.accepted'));
        $this->assertSame($autre['id'], $rep->json('purchase_returns.rejected.0.id'));
        $this->assertStringContainsString('déjà été retourné', $rep->json('purchase_returns.rejected.0.reason'));
        $this->assertEquals($stock, $this->aliment->fresh()->stock_qty, 'le stock ne descend pas une seconde fois');
        $this->assertSame(2, PurchaseReturn::count());
        $this->assertSame(1, AccountingEntry::where('source_type', 'purchase_return')->count());
    }

    public function test_une_ligne_d_achat_ne_peut_etre_retournee_qu_une_fois_au_niveau_de_la_base(): void
    {
        $achat = $this->acheter(100000);
        $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);

        $ligne = PurchaseReturn::firstOrFail();

        $this->expectException(UniqueConstraintViolationException::class);

        PurchaseReturn::create([
            'purchase_id' => $achat->id, 'product_id' => $ligne->product_id, 'qty' => 1, 'reason' => 'doublon',
            'return_batch_id' => (string) Str::uuid(), 'purchase_line_id' => $ligne->purchase_line_id,
        ]);
    }

    public function test_un_retour_d_avant_le_ticket_marque_l_achat_comme_deja_retourne(): void
    {
        $achat = $this->acheter(100000);
        // Retour « à l'ancienne » : une ligne sans lot ni ligne d'achat, et aucun marqueur sur l'achat.
        $ligne = $achat->lines->first();
        PurchaseReturn::create(['purchase_id' => $achat->id, 'product_id' => $ligne->product_id, 'qty' => $ligne->qty, 'reason' => 'ancien']);
        $stock = $this->aliment->fresh()->stock_qty;

        $r = $this->retour($achat);
        $rep = $this->pousser($this->acheteur, ['purchase_returns' => [$r]]);

        $this->assertStringContainsString('déjà été retourné', $rep->json('purchase_returns.rejected.0.reason'));
        $this->assertEquals($stock, $this->aliment->fresh()->stock_qty);
    }

    // ------------------------------------------------------------------
    // Refus : stock, exercice, écriture, validation. Rien ne bouge.
    // ------------------------------------------------------------------

    private function instantane(): array
    {
        return [
            'aliment' => (string) $this->aliment->fresh()->stock_qty,
            'medicament' => (string) $this->medicament->fresh()->stock_qty,
            'ecritures' => AccountingEntry::count(),
            'retours' => PurchaseReturn::count(),
            'mouvements' => StockMovement::count(),
            'caisse' => (string) $this->caisse->fresh()->balance,
            'dettes' => Payable::get(['id', 'amount', 'amount_paid', 'status'])->toArray(),
        ];
    }

    public function test_un_stock_insuffisant_refuse_le_retour_et_ne_laisse_rien_derriere(): void
    {
        $achat = $this->acheter(40000);
        // La marchandise a été consommée entre-temps : il reste 3 aliments pour 10 à rendre.
        $this->aliment->update(['stock_qty' => 3]);
        $avant = $this->instantane();

        $r = $this->retour($achat);
        $rep = $this->pousser($this->acheteur, ['purchase_returns' => [$r]]);

        $this->assertSame([], $rep->json('purchase_returns.accepted'));
        $this->assertStringContainsString('Stock insuffisant', $rep->json('purchase_returns.rejected.0.reason'));
        $this->assertSame($avant, $this->instantane(), 'ni stock, ni dette, ni caisse, ni écriture ne bougent');
        $this->assertNull($achat->fresh()->returned_at);
        // Le stock n'est jamais descendu sous zéro : même la ligne « vitamines » (stock suffisant) n'a pas été retournée.
        $this->assertEquals(6, $this->medicament->fresh()->stock_qty);
    }

    public function test_deux_lignes_du_meme_produit_sont_additionnees_pour_le_controle_du_stock(): void
    {
        $achat = app(RecordPurchaseAction::class)->execute(
            $this->fournisseur->id,
            [
                ['product_id' => $this->aliment->id, 'qty' => 6, 'unit_price' => 1000],
                ['product_id' => $this->aliment->id, 'qty' => 6, 'unit_price' => 1000],
            ],
            'especes', $this->caisse->id, 12000, (string) Str::uuid(),
        );
        // Stock = 5 + 12 = 17 ; on en consomme 10 : il reste 7, soit assez pour une ligne (6) mais pas pour les deux (12).
        $this->aliment->update(['stock_qty' => 7]);
        $avant = $this->instantane();

        $rep = $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);

        $this->assertStringContainsString('Stock insuffisant', $rep->json('purchase_returns.rejected.0.reason'));
        $this->assertSame($avant, $this->instantane());
    }

    public function test_un_exercice_clos_refuse_le_retour_sans_laisser_ni_stock_ni_dette_faux(): void
    {
        $achat = $this->acheter(40000);
        FiscalYear::query()->update(['status' => 'cloture']);
        $avant = $this->instantane();

        $r = $this->retour($achat);
        $rep = $this->pousser($this->acheteur, ['purchase_returns' => [$r]]);

        $this->assertSame([], $rep->json('purchase_returns.accepted'));
        $this->assertSame($r['id'], $rep->json('purchase_returns.rejected.0.id'));
        $this->assertNotEmpty($rep->json('purchase_returns.rejected.0.reason'));
        $this->assertSame($avant, $this->instantane());
        $this->assertNull($achat->fresh()->returned_at);
    }

    public function test_un_exercice_absent_pour_la_date_du_retour_refuse_le_retour(): void
    {
        $achat = $this->acheter(40000);
        // L'exercice couvre toute l'année ; on le raccourcit pour qu'il ne couvre plus aujourd'hui.
        FiscalYear::query()->update(['end_date' => now()->subDay()->toDateString()]);
        $avant = $this->instantane();

        $rep = $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);

        $this->assertSame([], $rep->json('purchase_returns.accepted'));
        $this->assertNotEmpty($rep->json('purchase_returns.rejected.0.reason'));
        $this->assertSame($avant, $this->instantane());
    }

    public function test_un_achat_sans_ecriture_d_origine_est_refuse_avec_motif(): void
    {
        $achat = $this->acheter(40000);
        $achat->update(['accounting_entry_id' => null]);
        $avant = $this->instantane();

        $rep = $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);

        $this->assertStringContainsString("pas d'écriture comptable", $rep->json('purchase_returns.rejected.0.reason'));
        $this->assertSame($avant, $this->instantane());
    }

    public function test_un_achat_paye_sans_compte_409_au_plan_est_refuse_et_rien_ne_bouge(): void
    {
        $achat = $this->acheter(100000);
        ChartOfAccount::where('code', '409')->delete();
        $avant = $this->instantane();

        $rep = $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);

        $this->assertStringContainsString('409', $rep->json('purchase_returns.rejected.0.reason'));
        $this->assertSame($avant, $this->instantane());
    }

    public function test_la_validation_rejette_element_par_element_jamais_l_envoi_entier(): void
    {
        $achat = $this->acheter(100000);
        $bon = $this->retour($achat);

        $rep = $this->pousser($this->acheteur, ['purchase_returns' => [
            ['id' => 'pas-un-uuid', 'purchase_id' => $achat->id, 'reason' => 'x', 'return_date' => now()->toDateString()],
            $this->retour($achat, ['reason' => '']),
            $this->retour($achat, ['purchase_id' => (string) Str::uuid()]),
            $this->retour($achat, ['return_date' => now()->addDays(3)->toDateString()]),
            $this->retour($achat, ['return_date' => now()->subDays(30)->toDateString()]),
            $bon,
        ]]);

        $this->assertSame([$bon['id']], $rep->json('purchase_returns.accepted'));
        $this->assertCount(5, $rep->json('purchase_returns.rejected'));
        $motifs = implode(' | ', array_column($rep->json('purchase_returns.rejected'), 'reason'));
        $this->assertStringContainsString('introuvable', $motifs);
        $this->assertStringContainsString('futur', $motifs);
        $this->assertStringContainsString('précéder', $motifs);
    }

    public function test_sans_le_droit_manage_achats_le_retour_et_le_remboursement_sont_rejetes_avec_motif(): void
    {
        $achat = $this->acheter(100000);
        $avant = $this->instantane();
        $r = $this->retour($achat);
        $b = $this->remboursement();

        $rep = $this->pousser($this->caissier, ['purchase_returns' => [$r], 'supplier_refunds' => [$b]]);

        $this->assertSame([], $rep->json('purchase_returns.accepted'));
        $this->assertSame([], $rep->json('supplier_refunds.accepted'));
        $this->assertSame($r['id'], $rep->json('purchase_returns.rejected.0.id'));
        $this->assertSame($b['id'], $rep->json('supplier_refunds.rejected.0.id'));
        $this->assertStringContainsString('rôle', $rep->json('purchase_returns.rejected.0.reason'));
        $this->assertStringContainsString('rôle', $rep->json('supplier_refunds.rejected.0.reason'));
        $this->assertSame($avant, $this->instantane());
    }

    // ------------------------------------------------------------------
    // Paquets : ordre et double décrément
    // ------------------------------------------------------------------

    public function test_un_paquet_achat_puis_retour_traite_l_achat_avant_son_retour(): void
    {
        $id = (string) Str::uuid();
        $r = [
            'id' => (string) Str::uuid(), 'purchase_id' => $id, 'reason' => 'Erreur de saisie', 'return_date' => now()->toDateString(),
        ];

        // Le retour est listé AVANT l'achat dans le corps : l'ordre de traitement est celui du serveur, pas du JSON.
        $rep = $this->pousser($this->acheteur, [
            'purchase_returns' => [$r],
            'purchases' => [[
                'id' => $id, 'supplier_id' => $this->fournisseur->id, 'payment_mode' => 'especes',
                'treasury_account_id' => $this->caisse->id, 'amount_paid' => 50000, 'purchase_date' => now()->toDateString(),
                'lines' => [['product_id' => $this->aliment->id, 'qty' => 10, 'unit_price' => 5000]],
            ]],
        ]);

        $this->assertSame([$id], $rep->json('purchases.accepted'));
        $this->assertSame([$r['id']], $rep->json('purchase_returns.accepted'), json_encode($rep->json('purchase_returns')));
        $this->assertEquals(5, $this->aliment->fresh()->stock_qty, 'entré puis ressorti : stock de départ');
        $this->assertEquals(0, $this->net('601'));
        $this->assertEquals(50000, $this->net('409'));
        $this->assertLesDeuxLivresConcordent();
    }

    public function test_un_paquet_reglement_puis_retour_puis_remboursement_est_traite_dans_l_ordre(): void
    {
        $achat = $this->acheter(0);
        $r = $this->retour($achat);
        $pay = [
            'id' => (string) Str::uuid(), 'supplier_id' => $this->fournisseur->id, 'treasury_account_id' => $this->caisse->id,
            'amount' => 30000, 'payment_date' => now()->toDateString(),
        ];
        $b = $this->remboursement(['amount' => 30000]);

        $rep = $this->pousser($this->acheteur, [
            'supplier_refunds' => [$b],
            'purchase_returns' => [$r],
            'supplier_payments' => [$pay],
        ]);

        $this->assertSame([$pay['id']], $rep->json('supplier_payments.accepted'));
        $this->assertSame([$r['id']], $rep->json('purchase_returns.accepted'));
        // Règlement 30 000 d'abord (reste 70 000 dus), puis retour : D401 70 000, D409 30 000 ; remboursement 30 000 accepté.
        $this->assertSame([$b['id']], $rep->json('supplier_refunds.accepted'), json_encode($rep->json('supplier_refunds')));
        $this->assertEquals(0, $this->net('401'));
        $this->assertEquals(0, $this->net('409'));
        $this->assertEquals(0, $this->net('531'));
        $this->assertLesDeuxLivresConcordent();
    }

    public function test_un_paquet_retour_et_sortie_de_stock_de_retour_ne_decremente_que_ce_qui_est_du(): void
    {
        $achat = $this->acheter(100000);   // stock 15 / 6
        $r = $this->retour($achat);

        $rep = $this->pousser($this->acheteur, [
            'purchase_returns' => [$r],
            'stock_adjustments' => [
                // Le poste (à tort) double lui-même le décrément du retour, de trois façons.
                ['client_ref' => (string) Str::uuid(), 'product_id' => $this->aliment->id, 'type' => 'sortie', 'quantity' => 10, 'reference_type' => 'purchase_return'],
                ['client_ref' => $r['id'], 'product_id' => $this->aliment->id, 'type' => 'sortie', 'quantity' => 10, 'reference_type' => 'adjustment'],
                ['client_ref' => $achat->id, 'product_id' => $this->aliment->id, 'type' => 'sortie', 'quantity' => 10, 'reference_type' => 'adjustment'],
            ],
        ]);

        $this->assertSame([$r['id']], $rep->json('purchase_returns.accepted'));
        $this->assertSame([], $rep->json('stock_adjustments.accepted'));
        $this->assertCount(3, $rep->json('stock_adjustments.rejected'));
        $this->assertStringContainsString('retour fournisseur', $rep->json('stock_adjustments.rejected.0.reason'));
        // 15 - 10 (retour) = 5, et pas 5 - 10 - 10 - 10.
        $this->assertEquals(5, $this->aliment->fresh()->stock_qty);
        $this->assertSame(1, StockMovement::where('product_id', $this->aliment->id)->where('type', 'sortie')->count());
    }

    public function test_une_sortie_de_stock_sans_rapport_avec_le_retour_s_applique_normalement(): void
    {
        $achat = $this->acheter(100000);
        $r = $this->retour($achat);
        $ref = (string) Str::uuid();

        $rep = $this->pousser($this->acheteur, [
            'purchase_returns' => [$r],
            // Une vraie perte d'inventaire du même produit : le retour ne l'annule pas.
            'stock_adjustments' => [['client_ref' => $ref, 'product_id' => $this->aliment->id, 'type' => 'sortie', 'quantity' => 2, 'reference_type' => 'adjustment']],
        ]);

        $this->assertSame([$ref], $rep->json('stock_adjustments.accepted'));
        $this->assertEquals(3, $this->aliment->fresh()->stock_qty);   // 15 - 10 (retour) - 2 (perte)
    }

    public function test_une_sortie_de_retour_est_refusee_aussi_apres_un_retour_deja_recu_dans_un_envoi_precedent(): void
    {
        $achat = $this->acheter(100000);
        $r = $this->retour($achat);
        $this->pousser($this->acheteur, ['purchase_returns' => [$r]]);

        $rep = $this->pousser($this->acheteur, ['stock_adjustments' => [
            ['client_ref' => $r['id'], 'product_id' => $this->aliment->id, 'type' => 'sortie', 'quantity' => 10, 'reference_type' => 'adjustment'],
        ]]);

        $this->assertSame([], $rep->json('stock_adjustments.accepted'));
        $this->assertEquals(5, $this->aliment->fresh()->stock_qty);
    }

    // ------------------------------------------------------------------
    // Remboursement (D8)
    // ------------------------------------------------------------------

    public function test_un_remboursement_entre_en_tresorerie_et_au_journal_et_reste_plafonne_a_la_creance(): void
    {
        $achat = $this->acheter(100000);
        $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);
        $this->assertEquals(100000, $this->net('409'));

        // 1) 60 000 sur 100 000 de créance.
        $b1 = $this->remboursement(['amount' => 60000]);
        $rep = $this->pousser($this->acheteur, ['supplier_refunds' => [$b1]]);
        $this->assertSame([$b1['id']], $rep->json('supplier_refunds.accepted'));
        $this->assertEquals(-40000, $this->caisse->fresh()->balance);   // -100 000 + 60 000
        $this->assertEquals(40000, $this->net('409'));
        $this->assertEquals(-40000, $this->net('531'));
        $this->assertEquals(60000, SupplierRefund::find($b1['id'])->applied_amount);
        $this->assertLesDeuxLivresConcordent();

        // 2) 70 000 demandés pour 40 000 restants : plafonné à 40 000, jamais 70 000 en caisse.
        $b2 = $this->remboursement(['amount' => 70000]);
        $rep = $this->pousser($this->acheteur, ['supplier_refunds' => [$b2]]);
        $this->assertSame([$b2['id']], $rep->json('supplier_refunds.accepted'));
        $refund = SupplierRefund::find($b2['id']);
        $this->assertEquals(70000, $refund->amount);
        $this->assertEquals(40000, $refund->applied_amount);
        $this->assertEquals(0, $this->caisse->fresh()->balance);
        $this->assertEquals(0, $this->net('409'));
        $this->assertLesDeuxLivresConcordent();

        // 3) Plus rien à rembourser : refus AVEC motif, aucune écriture à zéro, aucune entrée en caisse.
        $b3 = $this->remboursement(['amount' => 10000]);
        $ecritures = AccountingEntry::count();
        $rep = $this->pousser($this->acheteur, ['supplier_refunds' => [$b3]]);
        $this->assertSame([], $rep->json('supplier_refunds.accepted'));
        $this->assertStringContainsString('aucune créance ouverte', $rep->json('supplier_refunds.rejected.0.reason'));
        $this->assertSame($ecritures, AccountingEntry::count());
        $this->assertEquals(0, $this->caisse->fresh()->balance);
        $this->assertNull(SupplierRefund::find($b3['id']));
    }

    public function test_un_remboursement_sans_aucun_retour_est_refuse_avec_motif(): void
    {
        $this->acheter(100000);   // payé mais NON retourné : aucune créance
        $b = $this->remboursement();
        $avant = $this->instantane();

        $rep = $this->pousser($this->acheteur, ['supplier_refunds' => [$b]]);

        $this->assertSame([], $rep->json('supplier_refunds.accepted'));
        $this->assertStringContainsString('aucune créance ouverte', $rep->json('supplier_refunds.rejected.0.reason'));
        $this->assertSame($avant, $this->instantane());
    }

    public function test_un_achat_retourne_a_credit_n_ouvre_aucune_creance_remboursable(): void
    {
        $achat = $this->acheter(0);
        $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);

        $rep = $this->pousser($this->acheteur, ['supplier_refunds' => [$this->remboursement()]]);

        $this->assertSame([], $rep->json('supplier_refunds.accepted'));
        $this->assertEquals(0, $this->caisse->fresh()->balance);
    }

    public function test_un_renvoi_de_remboursement_n_encaisse_pas_deux_fois_meme_apres_cloture(): void
    {
        $achat = $this->acheter(100000);
        $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);
        $b = $this->remboursement(['amount' => 30000]);
        $this->pousser($this->acheteur, ['supplier_refunds' => [$b]]);
        $solde = $this->caisse->fresh()->balance;
        $ecritures = AccountingEntry::count();

        FiscalYear::query()->update(['status' => 'cloture']);
        $rep = $this->pousser($this->acheteur, ['supplier_refunds' => [$b]]);

        $this->assertSame([$b['id']], $rep->json('supplier_refunds.accepted'));
        $this->assertEquals($solde, $this->caisse->fresh()->balance);
        $this->assertSame($ecritures, AccountingEntry::count());
        $this->assertSame(1, SupplierRefund::count());
    }

    public function test_un_remboursement_sur_exercice_clos_est_refuse_et_la_caisse_ne_bouge_pas(): void
    {
        $achat = $this->acheter(100000);
        $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);
        FiscalYear::query()->update(['status' => 'cloture']);
        $solde = $this->caisse->fresh()->balance;

        $b = $this->remboursement();
        $rep = $this->pousser($this->acheteur, ['supplier_refunds' => [$b]]);

        $this->assertSame([], $rep->json('supplier_refunds.accepted'));
        $this->assertNotEmpty($rep->json('supplier_refunds.rejected.0.reason'));
        $this->assertEquals($solde, $this->caisse->fresh()->balance);
        $this->assertNull(SupplierRefund::find($b['id']));
    }

    public function test_un_remboursement_sans_compte_comptable_de_tresorerie_est_refuse_sans_argent_fantome(): void
    {
        $achat = $this->acheter(100000);
        $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);
        $this->caisse->update(['account_code' => '599']);   // code absent du plan comptable
        $solde = $this->caisse->fresh()->balance;

        $b = $this->remboursement();
        $rep = $this->pousser($this->acheteur, ['supplier_refunds' => [$b]]);

        $this->assertSame([], $rep->json('supplier_refunds.accepted'));
        $this->assertStringContainsString('Écriture impossible', $rep->json('supplier_refunds.rejected.0.reason'));
        $this->assertEquals($solde, $this->caisse->fresh()->balance, 'jamais d\'argent encaissé sans écriture');
        $this->assertNull(SupplierRefund::find($b['id']));
    }

    public function test_la_validation_des_remboursements_est_element_par_element(): void
    {
        $achat = $this->acheter(100000);
        $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);
        $bon = $this->remboursement(['amount' => 1000]);

        $rep = $this->pousser($this->acheteur, ['supplier_refunds' => [
            $this->remboursement(['amount' => 0]),
            $this->remboursement(['id' => 'x']),
            $this->remboursement(['supplier_id' => (string) Str::uuid()]),
            $this->remboursement(['treasury_account_id' => (string) Str::uuid()]),
            $bon,
        ]]);

        $this->assertSame([$bon['id']], $rep->json('supplier_refunds.accepted'));
        $this->assertCount(4, $rep->json('supplier_refunds.rejected'));
    }

    // ------------------------------------------------------------------
    // Tirage, référentiels ignorés, garde-fou source
    // ------------------------------------------------------------------

    public function test_le_tirage_incremental_sert_le_marqueur_de_retour_et_la_creance_ouverte(): void
    {
        $achat = $this->acheter(100000);
        $avant = now()->subMinute()->toIso8601String();

        $pull = $this->actingAs($this->acheteur, 'sanctum')->getJson('/api/sync/pull?since='.urlencode($avant))->assertOk();
        $ligne = collect($pull->json('purchases'))->firstWhere('id', $achat->id);
        $this->assertNull($ligne['returned_at']);
        $this->assertSame([], $pull->json('supplier_credits'));

        $this->pousser($this->acheteur, ['purchase_returns' => [$this->retour($achat)]]);

        $pull = $this->actingAs($this->acheteur, 'sanctum')->getJson('/api/sync/pull?since='.urlencode($avant))->assertOk();
        $ligne = collect($pull->json('purchases'))->firstWhere('id', $achat->id);
        $this->assertNotNull($ligne, "l'achat retourné redescend au tirage incrémental");
        $this->assertNotNull($ligne['returned_at']);
        $this->assertEquals(100000, $ligne['supplier_credit']);
        $this->assertFalse($ligne['has_debt']);
        $this->assertEquals(100000, $pull->json('supplier_credits.0.open_credit'));
        $this->assertSame($this->fournisseur->id, $pull->json('supplier_credits.0.supplier_id'));

        // Après un remboursement partiel, la créance servie est la créance OUVERTE.
        $this->pousser($this->acheteur, ['supplier_refunds' => [$this->remboursement(['amount' => 25000])]]);
        $pull = $this->actingAs($this->acheteur, 'sanctum')->getJson('/api/sync/pull')->assertOk();
        $this->assertEquals(75000, $pull->json('supplier_credits.0.open_credit'));

        // Un achat non touché depuis n'est pas resservi.
        $plusTard = now()->addMinute()->toIso8601String();
        $pull = $this->actingAs($this->acheteur, 'sanctum')->getJson('/api/sync/pull?since='.urlencode($plusTard))->assertOk();
        $this->assertNull(collect($pull->json('purchases'))->firstWhere('id', $achat->id));
    }

    public function test_les_deux_nouvelles_tables_ne_sont_pas_des_referentiels_ignores(): void
    {
        $achat = $this->acheter(100000);

        $rep = $this->pousser($this->acheteur, [
            'purchase_returns' => [$this->retour($achat)],
            'supplier_refunds' => [$this->remboursement()],
            'payables' => [['id' => 'x']],
        ]);

        // Seul `payables` (vrai référentiel) est ignoré et compté.
        $this->assertSame(1, $rep->json('referentiels_ignored'));
    }

    // ------------------------------------------------------------------
    // Plan comptable et migrations
    // ------------------------------------------------------------------

    public function test_le_compte_409_existe_par_la_migration_de_rattrapage_et_par_la_semence_sans_doublon(): void
    {
        // Base migrée SANS semence : seul le rattrapage a pu ouvrir le compte (cas d'une base de production déjà semée).
        ChartOfAccount::where('code', '409')->get()->each->delete();
        $migration = require base_path('database/migrations/2026_10_09_000008_add_account_409_suppliers_debtors.php');
        $migration->up();
        $migration->up();   // idempotente

        $compte = ChartOfAccount::where('code', '409')->get();
        $this->assertCount(1, $compte);
        $this->assertSame('Fournisseurs débiteurs', $compte->first()->label);
        $this->assertEquals(4, $compte->first()->class);

        // La semence des bases neuves le pose aussi, une seule fois même rejouée.
        $this->seed(\Database\Seeders\ChartOfAccountsSeeder::class);
        $this->seed(\Database\Seeders\ChartOfAccountsSeeder::class);
        $this->assertSame(1, ChartOfAccount::where('code', '409')->count());
    }

    public function test_la_migration_marque_les_retours_d_avant_comme_retournes_sans_leur_inventer_d_ecriture(): void
    {
        $achat = $this->acheter(100000);
        $migration = require base_path('database/migrations/2026_10_09_000006_add_return_columns_to_purchases_and_purchase_returns.php');

        // État d'AVANT le ticket : colonnes absentes, un retour « à l'ancienne » déjà passé.
        $migration->down();
        DB::table('purchase_returns')->insert([
            'id' => (string) Str::uuid(), 'purchase_id' => $achat->id, 'product_id' => $this->aliment->id,
            'qty' => 10, 'reason' => 'ancien retour', 'created_at' => '2026-09-01 10:00:00', 'updated_at' => '2026-09-01 10:00:00',
        ]);
        $migration->up();

        $achat = $achat->fresh();
        $this->assertNotNull($achat->returned_at, 'un second retour décrémenterait une seconde fois');
        $this->assertSame('2026-09-01', $achat->returned_at->format('Y-m-d'));
        $this->assertEquals(0, $achat->supplier_credit, 'aucune créance inventée pour un retour passé sans écriture');
        $this->assertNotNull(PurchaseReturn::first()->return_batch_id);
        $this->assertSame(0, AccountingEntry::where('source_type', 'purchase_return')->count());
    }

    public function test_garde_fou_source_le_retour_n_est_ecrit_que_par_le_service(): void
    {
        $racine = base_path('app');
        $fichiers = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($racine));
        $ecrivains = [];

        foreach ($fichiers as $f) {
            if ($f->getExtension() !== 'php') {
                continue;
            }
            $code = file_get_contents($f->getPathname());
            // Écriture du marqueur ou de la créance d'un achat, ou création d'une ligne de retour.
            if (preg_match("/(forceFill|fill|update|create)\(\[[^\]]*'(returned_at|supplier_credit)'|PurchaseReturn::create\(|new PurchaseReturn\(/s", $code)) {
                $ecrivains[] = str_replace('\\', '/', substr($f->getPathname(), strlen($racine) + 1));
            }
        }

        sort($ecrivains);
        $this->assertSame(['Services/PurchaseReturnService.php'], $ecrivains, 'Le retour ne s\'écrit que par PurchaseReturnService.');

        $page = file_get_contents(app_path('Livewire/Achats/ListeAchats.php'));
        $this->assertStringNotContainsString("increment('balance'", $page, 'la page ne touche plus la trésorerie en direct');
        $this->assertStringNotContainsString('AdjustStockAction', $page);
    }
}
