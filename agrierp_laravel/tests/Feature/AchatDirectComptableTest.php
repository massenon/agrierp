<?php

namespace Tests\Feature;

use App\Livewire\Achats\BonsCommande;
use App\Livewire\Achats\EnregistrerAchat;
use App\Models\AccountingEntry;
use App\Models\AuditLog;
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
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.22 — L'ACHAT DIRECT REFUSE EXACTEMENT COMME LA RÉCEPTION D'UN BON (15.21).
 *
 * Avant : `RecordPurchaseAction` en mode par défaut laissait achat + stock + dette + décaissement SANS écriture quand un
 * compte (601, 445, 401, trésorerie) manquait — un simple avertissement —, et un exercice clos n'était refusé que si les
 * comptes existaient (la vérification de compte précédait celle de l'exercice, d'où un refus « contourné » ; sinon la
 * page Livewire laissait remonter l'exception : erreur 500). Un total nul passait avec zéro écriture.
 *
 * Désormais : tout refus annule TOUT (même transaction), la page affiche un message français, rien n'est persisté.
 * Chaque chiffre comptable est recalculé indépendamment (somme SQL brute des lignes d'écriture par compte).
 */
class AchatDirectComptableTest extends TestCase
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

        Permission::findOrCreate('manage-achats', 'web');
        Role::findOrCreate('acheteur', 'web')->givePermissionTo('manage-achats');

        $this->acheteur = User::create([
            'name' => 'Acheteur', 'username' => 'acheteur', 'email' => 'acheteur@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->acheteur->assignRole('acheteur');

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

        foreach ([['601', 'Achats', 6], ['401', 'Fournisseurs', 4], ['445', 'TVA récupérable', 4], ['531', 'Caisse', 5]] as [$code, $libelle, $classe]) {
            ChartOfAccount::firstOrCreate(['code' => $code], ['label' => $libelle, 'class' => $classe, 'is_active' => true]);
        }
    }

    /** Panier : 10 sacs à 5 900 TTC = 59 000 (HT 50 000, TVA 9 000), ou à $prix. */
    private function acheter(float $regle, float $prix = 5900)
    {
        return Livewire::actingAs($this->acheteur)->test(EnregistrerAchat::class)
            ->set('supplierId', $this->fournisseur->id)
            ->set('treasuryAccountId', $this->caisse->id)
            ->set('paymentMode', 'especes')
            ->set('cart', [[
                'product_id' => $this->aliment->id, 'name' => $this->aliment->name, 'unit' => 'sac',
                'qty' => 10, 'unit_price' => $prix,
            ]])
            ->set('amountPaid', $regle)
            ->call('submitAchat');
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

    private function assertAucunResidu(): void
    {
        $this->assertSame(0, Purchase::count(), 'Aucun achat ne doit subsister.');
        $this->assertSame(0, PurchaseLine::count());
        $this->assertSame(0, Payable::count(), 'Aucune dette orpheline.');
        $this->assertSame(0, AccountingEntry::count());
        $this->assertSame(0, StockMovement::count());
        $this->assertEquals(5, (float) $this->aliment->fresh()->stock_qty, 'Le stock ne doit pas bouger.');
        $this->assertEquals(100_000, (float) $this->caisse->fresh()->balance, 'La caisse ne doit pas bouger.');
        $this->assertSame(0, AuditLog::where('action', 'purchase.recorded')->count(), 'Aucune trace de succès.');
    }

    // ------------------------------------------------------------------ succès nominal inchangé

    public function test_achat_direct_nominal_paiement_partiel_garde_ses_cinq_effets(): void
    {
        $this->acheter(20_000)->assertDispatched('toast', type: 'success')->assertNotDispatched('toast', type: 'error');

        $achat = Purchase::firstOrFail();
        $this->assertEquals(59_000, (float) $achat->total);
        $this->assertNotNull($achat->accounting_entry_id);
        $this->assertEquals(15, (float) $this->aliment->fresh()->stock_qty);
        $this->assertEquals(80_000, (float) $this->caisse->fresh()->balance);
        $dette = Payable::firstOrFail();
        $this->assertEquals(59_000, (float) $dette->amount);
        $this->assertEquals(20_000, (float) $dette->amount_paid);

        // Recalcul indépendant : 601 = 50 000 D, 445 = 9 000 D, 531 = 20 000 C, 401 = 39 000 C.
        $this->assertSame(50_000.0, $this->net('601'));
        $this->assertSame(9_000.0, $this->net('445'));
        $this->assertSame(-20_000.0, $this->net('531'));
        $this->assertSame(-39_000.0, $this->net('401'));
        $this->assertSame(1, AccountingEntry::count());
    }

    public function test_achat_direct_nominal_integralement_regle_sans_dette(): void
    {
        $this->acheter(59_000)->assertDispatched('toast', type: 'success');

        $this->assertSame(0, Payable::count());
        $this->assertSame(-59_000.0, $this->net('531'));
        $this->assertSame(0.0, $this->net('401'));
        $this->assertEquals(41_000, (float) $this->caisse->fresh()->balance);
    }

    // ------------------------------------------------------------------ refus : rien n'est écrit

    public function test_compte_601_manquant_refuse_sans_residu(): void
    {
        ChartOfAccount::where('code', '601')->delete();

        $this->acheter(20_000)->assertDispatched('toast', type: 'error');

        $this->assertAucunResidu();
    }

    public function test_compte_de_dette_401_manquant_refuse_sans_residu(): void
    {
        ChartOfAccount::where('code', '401')->delete();

        $this->acheter(20_000)->assertDispatched('toast', type: 'error');

        $this->assertAucunResidu();
    }

    public function test_compte_de_tva_445_manquant_refuse_sans_residu(): void
    {
        ChartOfAccount::where('code', '445')->delete();

        $this->acheter(20_000)->assertDispatched('toast', type: 'error');

        $this->assertAucunResidu();
    }

    public function test_compte_de_tresorerie_manquant_refuse_sans_residu(): void
    {
        ChartOfAccount::where('code', '531')->delete();

        $this->acheter(20_000)->assertDispatched('toast', type: 'error');

        $this->assertAucunResidu();
    }

    public function test_exercice_clos_refuse_proprement_sans_residu(): void
    {
        $this->exercice->update(['status' => 'cloture']);

        $this->acheter(20_000)->assertDispatched('toast', type: 'error')->assertNotDispatched('toast', type: 'success');

        $this->assertAucunResidu();
    }

    public function test_exercice_clos_est_refuse_meme_quand_un_compte_manque(): void
    {
        // Le contournement d'avant : un compte absent court-circuitait la vérification de l'exercice.
        $this->exercice->update(['status' => 'cloture']);
        ChartOfAccount::where('code', '401')->delete();

        $this->acheter(20_000)->assertDispatched('toast', type: 'error')->assertNotDispatched('toast', type: 'success');

        $this->assertAucunResidu();
    }

    public function test_exercice_absent_refuse_proprement_sans_residu(): void
    {
        $this->exercice->delete();

        $this->acheter(20_000)->assertDispatched('toast', type: 'error');

        $this->assertAucunResidu();
    }

    public function test_le_refus_garde_le_panier_et_dit_pourquoi_en_francais(): void
    {
        ChartOfAccount::where('code', '601')->delete();

        $page = $this->acheter(20_000);

        $this->assertCount(1, $page->get('cart'), 'Le panier est conservé pour corriger et réessayer.');
        $page->assertDispatched('toast', fn ($nom, $params) => ($params['type'] ?? null) === 'error'
            && str_contains($params['message'], 'Achat refusé')
            && str_contains($params['message'], 'plan comptable'));
    }

    // ------------------------------------------------------------------ prix zéro

    public function test_achat_direct_a_total_nul_est_refuse_sans_residu(): void
    {
        $this->acheter(0, 0)->assertDispatched('toast', type: 'error');

        $this->assertAucunResidu();
    }

    public function test_reception_d_un_bon_a_prix_zero_est_refusee_sans_residu(): void
    {
        $bon = PurchaseOrder::create(['supplier_id' => $this->fournisseur->id, 'status' => 'envoye']);
        PurchaseOrderLine::create([
            'purchase_order_id' => $bon->id, 'product_id' => $this->aliment->id, 'qty' => 10, 'estimated_unit_price' => 0,
        ]);

        Livewire::actingAs($this->acheteur)->test(BonsCommande::class)
            ->set('receivingOrderId', $bon->id)
            ->call('confirmReceiveOrder')
            ->assertDispatched('toast', type: 'error');

        $this->assertAucunResidu();
        $this->assertSame('envoye', $bon->fresh()->status, 'Le bon reste à recevoir.');
    }

    // ------------------------------------------------------------------ poste hors ligne : même règle, par enregistrement

    private function pousser(array $achats)
    {
        return $this->actingAs($this->acheteur, 'sanctum')->postJson('/api/sync/push', ['purchases' => $achats]);
    }

    private function achatPoste(array $remplace = []): array
    {
        return array_merge([
            'id' => '88888888-8888-4888-8888-888888888888',
            'supplier_id' => $this->fournisseur->id,
            'payment_mode' => 'especes',
            'treasury_account_id' => $this->caisse->id,
            'amount_paid' => 20_000,
            'purchase_date' => now()->toDateString(),
            'lines' => [['product_id' => $this->aliment->id, 'qty' => 10, 'unit_price' => 5900]],
        ], $remplace);
    }

    public function test_un_achat_de_poste_sans_compte_est_rejete_avec_motif_sans_residu_ni_500(): void
    {
        ChartOfAccount::where('code', '601')->delete();

        $reponse = $this->pousser([$this->achatPoste()]);

        $reponse->assertOk()
            ->assertJsonPath('purchases.accepted', [])
            ->assertJsonPath('purchases.rejected.0.id', '88888888-8888-4888-8888-888888888888');
        $this->assertStringContainsString('plan comptable', $reponse->json('purchases.rejected.0.reason'));
        $this->assertAucunResidu();
    }

    public function test_un_achat_de_poste_a_total_nul_est_rejete_avec_motif(): void
    {
        $reponse = $this->pousser([$this->achatPoste(['amount_paid' => 0, 'lines' => [['product_id' => $this->aliment->id, 'qty' => 3, 'unit_price' => 0]]])]);

        $reponse->assertOk()->assertJsonPath('purchases.accepted', []);
        $this->assertStringContainsString('total est nul', $reponse->json('purchases.rejected.0.reason'));
        $this->assertAucunResidu();
    }

    public function test_un_achat_de_poste_conforme_reste_accepte(): void
    {
        $this->pousser([$this->achatPoste()])->assertOk()->assertJsonPath('purchases.accepted.0', '88888888-8888-4888-8888-888888888888');

        $this->assertNotNull(Purchase::findOrFail('88888888-8888-4888-8888-888888888888')->accounting_entry_id);
        $this->assertSame(50_000.0, $this->net('601'));
    }

    // ------------------------------------------------------------------ garde-fou source

    public function test_l_action_ne_laisse_plus_d_achat_sans_ecriture(): void
    {
        $source = file_get_contents(app_path('Actions/RecordPurchaseAction.php'));

        $this->assertStringNotContainsString('ecritureObligatoire', $source, 'Plus de mode « écriture facultative » : tout achat exige son écriture.');
        $this->assertStringNotContainsString('purchase.accounting_entry_missing', $source);
    }
}
