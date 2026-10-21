<?php

namespace Tests\Feature;

use App\Actions\RecordPurchaseAction;
use App\Livewire\Achats\ListeAchats;
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
use App\Models\Supplier;
use App\Models\SupplierRefund;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.20 — LA PAGE WEB « LISTE D'ACHATS » : RETOUR FOURNISSEUR ET REMBOURSEMENT.
 *
 * Défauts web corrigés par ce ticket, chacun verrouillé ici :
 *  - `confirmReturnPurchase` décrémentait le stock sans toucher dette, trésorerie ni journal, et pouvait être rejoué
 *    (double retour = double décrément, stock négatif) ;
 *  - `submitRefund` créditait la trésorerie SANS écriture ni fournisseur (les deux livres divergeaient) ;
 *  - aucune des quatre actions n'exigeait de droit (D11 : `manage-achats`).
 *
 * Les tests « non-régression » du premier bloc décrivent ce que la page faisait déjà et qui reste vrai.
 */
class ListeAchatsRetourWebTest extends TestCase
{
    use RefreshDatabase;

    private User $acheteur;

    private User $lecteur;

    private Supplier $fournisseur;

    private Product $aliment;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-achats', 'manage-achats'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('acheteur', 'web')->givePermissionTo(['view-achats', 'manage-achats']);
        Role::findOrCreate('lecteur', 'web')->givePermissionTo(['view-achats']);

        $this->acheteur = $this->utilisateur('acheteur');
        $this->lecteur = $this->utilisateur('lecteur');

        $this->fournisseur = Supplier::create(['name' => 'Provenderie du Plateau', 'category' => 'Aliments', 'is_active' => true]);

        $this->aliment = Product::create([
            'sku' => 'ALI-PONTE-25', 'name' => 'Aliment ponte 25kg',
            'category_id' => ProductCategory::create(['label' => 'Aliments', 'is_active' => true])->id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'price_min' => 8000, 'price_max' => 8000,
            'stock_qty' => 5, 'is_active' => true,
        ]);

        $this->caisse = TreasuryAccount::create([
            'label' => 'Caisse Physique', 'account_code' => '531', 'type' => 'caisse', 'balance' => 0, 'is_active' => true,
        ]);

        FiscalYear::create([
            'year' => (int) now()->format('Y'),
            'start_date' => now()->startOfYear()->toDateString(),
            'end_date' => now()->endOfYear()->toDateString(),
            'status' => 'ouvert',
        ]);

        foreach ([['601', 'Achats', 6], ['401', 'Fournisseurs', 4], ['409', 'Fournisseurs débiteurs', 4], ['531', 'Caisse', 5]] as [$code, $libelle, $classe]) {
            ChartOfAccount::firstOrCreate(['code' => $code], ['label' => $libelle, 'class' => $classe, 'is_active' => true]);
        }
    }

    private function utilisateur(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    private function acheter(float $regle): Purchase
    {
        return app(RecordPurchaseAction::class)->execute(
            $this->fournisseur->id,
            [['product_id' => $this->aliment->id, 'qty' => 10, 'unit_price' => 10000]],
            $regle > 0 ? 'especes' : 'credit', $this->caisse->id, $regle, (string) Str::uuid(),
        );
    }

    private function page(?User $u = null)
    {
        return Livewire::actingAs($u ?? $this->acheteur)->test(ListeAchats::class);
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
        $this->assertEquals($comptes, round((float) $l->net, 2), 'Les deux livres de trésorerie divergent.');
    }

    private function retournerParLaPage(Purchase $achat, string $motif = "Erreur de saisie / d'article")
    {
        return $this->page()
            ->set('returningPurchaseId', $achat->id)
            ->set('returnReason', $motif)
            ->call('confirmReturnPurchase');
    }

    // ---------------------------------------------------------------------
    // Non-régression : ce que la page faisait déjà et qui reste vrai
    // ---------------------------------------------------------------------

    public function test_non_regression_le_motif_est_obligatoire(): void
    {
        $achat = $this->acheter(100000);

        $this->page()->set('returningPurchaseId', $achat->id)->set('returnReason', '')
            ->call('confirmReturnPurchase')->assertHasErrors(['returnReason']);

        $this->assertSame(0, PurchaseReturn::count());
        $this->assertEquals(15, $this->aliment->fresh()->stock_qty);
    }

    public function test_non_regression_le_retour_cree_une_ligne_de_retour_par_ligne_d_achat_et_decremente_le_stock(): void
    {
        $achat = $this->acheter(100000);

        $this->retournerParLaPage($achat)->assertDispatched('toast')->assertHasNoErrors();

        $this->assertSame(1, PurchaseReturn::where('purchase_id', $achat->id)->count());
        $this->assertEquals(5, $this->aliment->fresh()->stock_qty);
        $this->assertDatabaseHas('stock_movements', ['reference_type' => 'purchase_return', 'type' => 'sortie']);
    }

    // ---------------------------------------------------------------------
    // Défaut 1 : le retour touche enfin dette, journal et créance
    // ---------------------------------------------------------------------

    public function test_le_retour_web_contre_passe_l_achat_et_annule_la_dette(): void
    {
        $achat = $this->acheter(30000);   // 70 000 dus
        $this->assertEquals(-70000, $this->net('401'));

        $this->retournerParLaPage($achat);

        $this->assertEquals(0, $this->net('601'));
        $this->assertEquals(0, $this->net('401'));
        $this->assertEquals(30000, $this->net('409'));
        $this->assertSame('soldee', Payable::where('purchase_id', $achat->id)->first()->status);
        $this->assertSame(0, Payable::whereColumn('amount_paid', '<', 'amount')->count());
        $this->assertEquals(30000, $achat->fresh()->supplier_credit);
        $this->assertLesDeuxLivresConcordent();
    }

    public function test_le_retour_web_est_idempotent_le_second_est_refuse_avec_motif_et_le_stock_ne_descend_pas_deux_fois(): void
    {
        $achat = $this->acheter(100000);
        $this->retournerParLaPage($achat);
        $ecritures = AccountingEntry::count();

        // Le stock a de quoi supporter un second décrément (5 + 10 de plus) : seul le garde « déjà retourné » protège.
        $this->aliment->update(['stock_qty' => 40]);

        $page = $this->retournerParLaPage($achat);

        $page->assertHasErrors(['returnReason']);
        $this->assertStringContainsString('déjà été retourné', $page->errors()->first('returnReason'));
        $this->assertEquals(40, $this->aliment->fresh()->stock_qty);
        $this->assertSame(1, PurchaseReturn::count());
        $this->assertSame($ecritures, AccountingEntry::count());
    }

    public function test_le_retour_web_refuse_un_stock_insuffisant_et_n_ecrit_rien(): void
    {
        $achat = $this->acheter(100000);
        $this->aliment->update(['stock_qty' => 4]);
        $ecritures = AccountingEntry::count();

        $page = $this->retournerParLaPage($achat);

        $this->assertStringContainsString('Stock insuffisant', $page->errors()->first('returnReason'));
        $this->assertEquals(4, $this->aliment->fresh()->stock_qty, 'jamais négatif');
        $this->assertSame(0, PurchaseReturn::count());
        $this->assertSame($ecritures, AccountingEntry::count());
        $this->assertNull($achat->fresh()->returned_at);
    }

    public function test_le_retour_web_sur_exercice_clos_est_refuse_proprement(): void
    {
        $achat = $this->acheter(100000);
        FiscalYear::query()->update(['status' => 'cloture']);

        $page = $this->retournerParLaPage($achat);

        $this->assertNotEmpty($page->errors()->first('returnReason'));
        $this->assertSame(0, PurchaseReturn::count());
        $this->assertEquals(15, $this->aliment->fresh()->stock_qty);
    }

    public function test_un_achat_retourne_est_signale_et_ne_propose_plus_de_retour(): void
    {
        $achat = $this->acheter(100000);

        $this->page()->assertSee("openReturnModal('{$achat->id}')", false)->assertDontSee('RETOURNÉ');

        $this->retournerParLaPage($achat);

        $this->page()->assertDontSee("openReturnModal('{$achat->id}')", false)->assertSee('RETOURNÉ');
    }

    // ---------------------------------------------------------------------
    // Défaut 2 : le remboursement entre en trésorerie ET au journal
    // ---------------------------------------------------------------------

    private function rembourserParLaPage(float $montant)
    {
        return $this->page()
            ->set('refundSupplierId', $this->fournisseur->id)
            ->set('refundAmount', $montant)
            ->set('refundDate', now()->toDateString())
            ->set('refundTreasuryAccountId', $this->caisse->id)
            ->call('submitRefund');
    }

    public function test_le_remboursement_web_passe_son_ecriture_et_les_deux_livres_concordent(): void
    {
        $achat = $this->acheter(100000);
        $this->retournerParLaPage($achat);
        $this->assertEquals(-100000, $this->caisse->fresh()->balance);

        $this->rembourserParLaPage(60000)->assertHasNoErrors()->assertDispatched('toast', type: 'success');

        $this->assertEquals(-40000, $this->caisse->fresh()->balance);
        $this->assertEquals(40000, $this->net('409'));
        $ecriture = AccountingEntry::where('source_type', 'supplier_refund')->firstOrFail();
        $this->assertEquals(60000, $ecriture->lines->sum('debit'));
        $this->assertEquals(60000, $ecriture->lines->sum('credit'));
        $this->assertSame(1, SupplierRefund::count());
        $this->assertSame($this->fournisseur->id, SupplierRefund::first()->supplier_id);
        $this->assertLesDeuxLivresConcordent();
    }

    public function test_le_remboursement_web_est_plafonne_a_la_creance_et_le_dit(): void
    {
        $achat = $this->acheter(100000);
        $this->retournerParLaPage($achat);

        $this->rembourserParLaPage(150000)->assertDispatched('toast', type: 'warning');

        $this->assertEquals(100000, SupplierRefund::first()->applied_amount);
        $this->assertEquals(0, $this->caisse->fresh()->balance);
        $this->assertEquals(0, $this->net('409'));
        $this->assertLesDeuxLivresConcordent();
    }

    public function test_le_remboursement_web_sans_creance_est_refuse_et_la_tresorerie_ne_bouge_pas(): void
    {
        $this->acheter(100000);   // payé, jamais retourné

        $page = $this->rembourserParLaPage(50000);

        $page->assertHasErrors(['refundAmount']);
        $this->assertStringContainsString('aucune créance ouverte', $page->errors()->first('refundAmount'));
        $this->assertEquals(-100000, $this->caisse->fresh()->balance);
        $this->assertSame(0, SupplierRefund::count());
        $this->assertSame(0, AccountingEntry::where('source_type', 'supplier_refund')->count());
        $this->assertLesDeuxLivresConcordent();
    }

    // ---------------------------------------------------------------------
    // Défaut 3 : aucune des quatre actions n'exigeait de droit (D11)
    // ---------------------------------------------------------------------

    public function test_sans_le_droit_manage_achats_les_quatre_actions_sont_interdites(): void
    {
        $achat = $this->acheter(100000);
        $this->retournerParLaPage($achat);
        $autre = $this->acheter(100000);
        $avant = [PurchaseReturn::count(), SupplierRefund::count(), AccountingEntry::count(), (string) $this->caisse->fresh()->balance];

        $lecteur = fn () => $this->page($this->lecteur);

        $lecteur()->call('openReturnModal', $autre->id)->assertForbidden();
        $lecteur()->set('returningPurchaseId', $autre->id)->set('returnReason', 'x')->call('confirmReturnPurchase')->assertForbidden();
        $lecteur()->call('openRefundModal')->assertForbidden();
        $lecteur()
            ->set('refundSupplierId', $this->fournisseur->id)->set('refundAmount', 1000)->set('refundDate', now()->toDateString())
            ->set('refundTreasuryAccountId', $this->caisse->id)->call('submitRefund')->assertForbidden();

        $this->assertSame($avant, [PurchaseReturn::count(), SupplierRefund::count(), AccountingEntry::count(), (string) $this->caisse->fresh()->balance]);
    }

    public function test_la_lecture_de_la_liste_reste_ouverte_au_simple_lecteur(): void
    {
        $this->acheter(100000);

        $this->page($this->lecteur)->assertOk();
    }
}
