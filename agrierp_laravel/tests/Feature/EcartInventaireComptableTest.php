<?php

namespace Tests\Feature;

use App\Actions\RecordStockAdjustmentEntryAction;
use App\Livewire\Stocks\GestionStocks;
use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseLine;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\User;
use App\Services\FinancialReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.41 (Sprint 14) — ÉCART D'INVENTAIRE : la PERTE comptabilisée.
 *
 * Quatrième et dernier flux du CDC (« vente, achat, paie, **perte** ») à ne
 * produire aucune écriture. L'écran l'annonçait lui-même à l'utilisateur depuis
 * le Sprint 6 : « l'écriture de charge exceptionnelle (compte 657) arrive avec
 * la Comptabilité ».
 *
 * Deux décisions à tenir : la contrepartie est le compte d'ACHATS (le projet ne
 * tient pas d'inventaire permanent), et un excédent ne produit RIEN.
 */
class EcartInventaireComptableTest extends TestCase
{
    use RefreshDatabase;

    private Product $produit;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-stocks', 'manage-stocks'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('admin', 'web');
        $role->givePermissionTo(['view-stocks', 'manage-stocks']);

        $user = User::create([
            'name' => 'Logisticien', 'email' => 'inventaire@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'),
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
            ['601', 'Achats de marchandises', 6],
            ['657', 'Charges exceptionnelles', 6],
        ] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }

        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);

        $this->produit = Product::create([
            'sku' => 'ALI-001', 'name' => 'Aliment ponte 25kg', 'category_id' => $categorie->id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'price_min' => 6_500, 'price_max' => 7_500,
            'tva_rate' => 0, 'stock_qty' => 40, 'is_active' => true,
        ]);

        // Historique d'achat : PMP de 6 500 F le sac.
        $fournisseur = Supplier::create(['name' => 'Provenderie', 'phone' => '+22997000000', 'is_active' => true]);
        $achat = Purchase::create([
            'supplier_id' => $fournisseur->id, 'payment_mode' => 'especes',
            'total' => 260_000, 'purchase_date' => now()->format('Y-m-d'),
        ]);
        PurchaseLine::create([
            'purchase_id' => $achat->id, 'product_id' => $this->produit->id,
            'qty' => 40, 'unit_price' => 6_500,
        ]);
    }

    private function soldeCompte(string $code): float
    {
        $compte = ChartOfAccount::where('code', $code)->firstOrFail();

        return round(
            (float) AccountingEntryLine::where('account_id', $compte->id)->sum('debit')
            - (float) AccountingEntryLine::where('account_id', $compte->id)->sum('credit'),
            2
        );
    }

    private function inventorier(float $comptagePhysique)
    {
        return Livewire::test(GestionStocks::class)
            ->set('adjProductId', $this->produit->id)
            ->set('adjPhysical', $comptagePhysique)
            ->set('adjReason', 'Comptage mensuel')
            ->call('validateAdjustment');
    }

    /** LE FLUX MANQUANT : un manquant devient une charge exceptionnelle. */
    public function test_a_shortfall_is_posted_as_an_exceptional_charge(): void
    {
        // 40 théoriques, 37 comptés → 3 sacs manquants à 6 500 = 19 500 F.
        $this->inventorier(37)->assertHasNoErrors();

        $ecriture = AccountingEntry::where('source_type', 'stock_adjustment')->firstOrFail();
        $parCompte = $ecriture->load('lines.account')->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertEquals(19_500, (float) $parCompte['657']->debit, 'Perte valorisee au PMP.');
        $this->assertEquals(19_500, (float) $parCompte['601']->credit);
        $this->assertEquals(37, (float) $this->produit->fresh()->stock_qty);
    }

    /**
     * ⚠️ VALORISÉE AU PMP, jamais au prix de vente : perdre une marchandise
     * coûte ce qu'elle a coûté, pas ce qu'elle aurait rapporté.
     */
    public function test_the_loss_is_valued_at_cost_not_at_selling_price(): void
    {
        $this->inventorier(39);

        $ecriture = AccountingEntry::where('source_type', 'stock_adjustment')->firstOrFail();

        $this->assertEquals(6_500, (float) $ecriture->total_debit, 'Un sac au PMP, pas au prix de vente.');
        $this->assertNotEquals(7_500, (float) $ecriture->total_debit);
    }

    /**
     * ⚠️ CONTREPARTIE AU COMPTE D'ACHATS. Le projet ne tient pas d'inventaire
     * permanent : la marchandise a déjà été passée en charge à l'achat.
     * L'écriture la RECLASSE, elle ne l'ajoute pas — sinon la perte serait
     * comptée deux fois.
     */
    public function test_the_loss_is_reclassified_not_added_to_total_charges(): void
    {
        $reports = app(FinancialReportService::class);
        $avant = $reports->compteResultat(now()->format('Y-m-d'));

        $this->inventorier(37);

        $apres = app(FinancialReportService::class)->compteResultat(now()->format('Y-m-d'));

        // 601 baisse de 19 500, 657 monte d'autant : le TOTAL des charges est
        // inchangé, seule leur nature change.
        $this->assertEquals(-19_500, $this->soldeCompte('601'));
        $this->assertEquals(19_500, $this->soldeCompte('657'));
        $this->assertEquals($avant['resultat_net'], $apres['resultat_net'],
            'Une reclassification ne change pas le resultat.');
    }

    /**
     * ⚠️ UN EXCÉDENT N'EST PAS UN PROFIT. Trouver plus que prévu signale une
     * entrée non saisie ; l'inscrire en produit exceptionnel transformerait une
     * erreur de saisie en enrichissement.
     */
    public function test_a_surplus_produces_no_entry_at_all(): void
    {
        $this->inventorier(45)->assertHasNoErrors();

        $this->assertEquals(0, AccountingEntry::count(), "Aucune ecriture sur un excedent.");
        $this->assertEquals(45, (float) $this->produit->fresh()->stock_qty, 'Mais le stock est bien regularise.');
    }

    /** Un écart nul ne produit ni mouvement ni écriture. */
    public function test_no_discrepancy_produces_nothing(): void
    {
        $this->inventorier(40);

        $this->assertEquals(0, AccountingEntry::count());
    }

    /**
     * Produit sans historique d'achat : la perte n'est pas chiffrable.
     * Signalée, jamais comptée zéro en silence.
     */
    public function test_a_product_without_a_known_cost_is_reported_not_silently_zeroed(): void
    {
        $oeufs = Product::create([
            'sku' => 'AVI-002', 'name' => 'Œufs de table', 'category_id' => $this->produit->category_id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 2_000, 'price_max' => 2_500,
            'tva_rate' => 0, 'stock_qty' => 100, 'is_active' => true,
        ]);

        $this->assertNull($oeufs->computePmp());
        $this->assertNull(app(RecordStockAdjustmentEntryAction::class)->execute($oeufs, -10));

        Livewire::test(GestionStocks::class)
            ->set('adjProductId', $oeufs->id)
            ->set('adjPhysical', 90)
            ->call('validateAdjustment')
            ->assertDispatched('toast', function (string $nom, array $params) {
                return str_contains($params['message'], 'non comptabilisée');
            });

        $this->assertEquals(90, (float) $oeufs->fresh()->stock_qty, 'Le stock est corrige malgre tout.');
    }

    /** Le Bilan reste équilibré après régularisation. */
    public function test_the_balance_sheet_stays_balanced(): void
    {
        $this->inventorier(35);

        $this->assertTrue(app(FinancialReportService::class)->bilan(now()->format('Y-m-d'))['is_balanced']);
    }
}
