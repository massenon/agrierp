<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\EtatsFinanciers;
use App\Livewire\Rapports\StocksSynth;
use App\Livewire\Stocks\GestionStocks;
use App\Livewire\Ventes\PosInterface;
use App\Models\AuditLog;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseLine;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.30 (Sprint 14) — STOCK NÉGATIF : alerte non bloquante et plancher
 * de valorisation.
 *
 * Le point qui compte : un stock négatif ne doit plus RETRANCHER de la valeur
 * du stock. Valorisé tel quel, un seul produit en anomalie faisait baisser
 * mécaniquement la valorisation de tous les autres — et l'actif du Bilan avec.
 *
 * Et l'alerte reste une ALERTE : la vente doit toujours pouvoir être
 * enregistrée, sous peine de perdre aussi la caisse, la TVA et l'écriture
 * comptable en plus du stock.
 */
class StockNegatifTest extends TestCase
{
    use RefreshDatabase;

    private Product $sain;

    private Product $enAnomalie;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-ventes', 'manage-ventes', 'view-stocks', 'manage-stocks', 'view-rapports', 'view-comptabilite'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('admin', 'web');
        $role->givePermissionTo(['view-ventes', 'manage-ventes', 'view-stocks', 'manage-stocks', 'view-rapports', 'view-comptabilite']);

        $user = User::create([
            'name' => 'Gérant', 'email' => 'stock@olouwachegoun.bj', 'password' => bcrypt('AgriERP@2026'),
        ]);
        $user->assignRole($role);
        $this->actingAs($user);

        $categorie = ProductCategory::create(['label' => 'Transformés', 'is_active' => true]);

        $this->sain = Product::create([
            'sku' => 'TRA-001', 'name' => 'Poulet fumé', 'category_id' => $categorie->id,
            'unit' => 'pièce', 'pricing_mode' => 'fourchette', 'price_min' => 3_000, 'price_max' => 5_000,
            'tva_rate' => 18, 'stock_qty' => 10, 'alert_threshold' => 2, 'is_active' => true,
        ]);

        $this->enAnomalie = Product::create([
            'sku' => 'TRA-002', 'name' => 'Poulet braisé', 'category_id' => $categorie->id,
            'unit' => 'pièce', 'pricing_mode' => 'fourchette', 'price_min' => 3_000, 'price_max' => 5_000,
            'tva_rate' => 18, 'stock_qty' => -7, 'alert_threshold' => 2, 'is_active' => true,
        ]);

        // PMP de 1 000 F sur les deux produits, via un historique d'achat réel.
        $fournisseur = Supplier::create(['name' => 'Provenderie', 'phone' => '+22997000000', 'is_active' => true]);
        $achat = Purchase::create([
            'supplier_id' => $fournisseur->id, 'purchase_date' => now()->format('Y-m-d'),
            'payment_mode' => 'especes', 'total' => 20_000,
        ]);

        foreach ([$this->sain, $this->enAnomalie] as $produit) {
            PurchaseLine::create([
                'purchase_id' => $achat->id, 'product_id' => $produit->id,
                'qty' => 10, 'unit_price' => 1_000,
            ]);
        }
    }

    // ------------------------------------------------------------- le modèle

    public function test_a_negative_stock_is_floored_at_zero_for_valuation(): void
    {
        $this->assertTrue($this->enAnomalie->stockEstNegatif());
        $this->assertEquals(0.0, $this->enAnomalie->quantiteValorisable());
        $this->assertEquals(7.0, $this->enAnomalie->quantiteManquante());
        $this->assertEquals(0.0, $this->enAnomalie->valeurStock());

        $this->assertFalse($this->sain->stockEstNegatif());
        $this->assertEquals(10_000.0, $this->sain->valeurStock(), '10 unites a 1 000 F de PMP.');
    }

    /** Sans PMP calculable, la valeur reste `null` — jamais zéro. */
    public function test_a_product_without_purchase_history_stays_unvaluable_not_worthless(): void
    {
        $oeufs = Product::create([
            'sku' => 'AVI-999', 'name' => 'Œufs de table', 'category_id' => $this->sain->category_id,
            'unit' => 'plateau', 'pricing_mode' => 'fourchette', 'price_min' => 2_000, 'price_max' => 2_500,
            'tva_rate' => 0, 'stock_qty' => 50, 'is_active' => true,
        ]);

        $this->assertNull($oeufs->computePmp());
        $this->assertNull($oeufs->valeurStock(), "Non valorisable n'est pas sans valeur.");
    }

    // ------------------------------------------------------- la valorisation

    /**
     * LE DÉFAUT CORRIGÉ : un produit en anomalie retranchait de la valeur des
     * autres.
     */
    public function test_a_negative_product_no_longer_subtracts_from_the_total_stock_value(): void
    {
        $valuation = Livewire::test(EtatsFinanciers::class)->instance()->stockValuation;

        // Ancien calcul : (10 × 1 000) + (−7 × 1 000) = 3 000 — faux.
        $this->assertEquals(10_000, $valuation['valeur'], 'Seul le produit sain porte de la valeur.');
        $this->assertEquals(1, $valuation['nb_negatifs']);
        $this->assertEquals(7, $valuation['qte_manquante']);
    }

    /** L'écart est affiché, jamais absorbé en silence. */
    public function test_the_discrepancy_is_shown_in_note_3(): void
    {
        Livewire::test(EtatsFinanciers::class)
            ->set('tab', 'notes')
            ->assertSee('produit(s) en stock négatif')
            ->assertSee('un actif ne peut pas être négatif');
    }

    /** Même plancher dans la gestion des stocks, et anomalie signalée. */
    public function test_the_stock_screen_floors_the_value_and_flags_the_anomaly(): void
    {
        $lignes = collect(Livewire::test(GestionStocks::class)->instance()->stockRows)
            ->keyBy(fn ($r) => $r['product']->sku);

        $this->assertEquals(0, $lignes['TRA-002']['valeur']);
        $this->assertTrue($lignes['TRA-002']['stock_negatif']);
        $this->assertEquals(10_000, $lignes['TRA-001']['valeur']);
        $this->assertFalse($lignes['TRA-001']['stock_negatif']);

        Livewire::test(GestionStocks::class)->assertSee('Entrée non saisie');
    }

    /** Et dans la synthèse par catégorie — une anomalie n'ampute plus sa filière. */
    public function test_the_category_summary_is_not_reduced_by_a_negative_product(): void
    {
        // ⚠️ `StocksSynth::mount()` exige une periode : le composant n'est pas
        // instanciable sans bornes, contrairement aux autres ecrans de stock.
        $lignes = collect(Livewire::test(StocksSynth::class, [
            'startDate' => now()->startOfMonth()->format('Y-m-d'),
            'endDate' => now()->endOfMonth()->format('Y-m-d'),
        ])->instance()->rows);

        $categorie = $lignes->first(fn ($r) => $r['category']->label === 'Transformés');

        $this->assertNotNull($categorie);
        $this->assertEquals(10_000, $categorie['valeur_stock']);
        $this->assertEquals(1, $categorie['negatifs']);
    }

    // ------------------------------------------------------------- le POS

    /** L'alerte prévient — et n'empêche jamais l'enregistrement. */
    public function test_selling_beyond_stock_warns_but_never_blocks(): void
    {
        $composant = Livewire::test(PosInterface::class)
            ->call('selectProduct', $this->sain->id)
            ->set('weightQty', 15)          // sur 10 en stock
            ->set('weightPrice', 45_000)
            ->call('confirmWeightAdd')
            ->assertHasNoErrors();

        $this->assertCount(1, $composant->get('cart'), 'La vente doit rester enregistrable.');

        $composant->assertDispatched('toast', function (string $nom, array $params) {
            return str_contains($params['message'], 'stock insuffisant')
                && $params['type'] === 'warning';
        });

        $this->assertEquals(1, AuditLog::where('action', 'pos.stock_insuffisant')->count(),
            "L'anomalie doit rester investigable.");
    }

    /** Une vente dans les limites du stock ne déclenche aucune alerte. */
    public function test_a_sale_within_stock_raises_no_warning(): void
    {
        Livewire::test(PosInterface::class)
            ->call('selectProduct', $this->sain->id)
            ->set('weightQty', 4)
            ->set('weightPrice', 12_000)
            ->call('confirmWeightAdd')
            ->assertDispatched('toast', function (string $nom, array $params) {
                return $params['type'] === 'success';
            });

        $this->assertEquals(0, AuditLog::where('action', 'pos.stock_insuffisant')->count());
    }

    /**
     * ⚠️ LE CAS QUE LE CUMUL SEUL ATTRAPE : deux lignes de 6 sur un stock de
     * 10. Aucune n'est en rupture prise isolément ; ensemble, elles le sont.
     */
    public function test_two_cart_lines_of_the_same_product_are_counted_together(): void
    {
        $composant = Livewire::test(PosInterface::class)
            ->call('selectProduct', $this->sain->id)
            ->set('weightQty', 6)
            ->set('weightPrice', 18_000)
            ->call('confirmWeightAdd');

        $this->assertEquals(0, AuditLog::where('action', 'pos.stock_insuffisant')->count(),
            'Six sur dix : aucune alerte attendue.');

        $composant->call('selectProduct', $this->sain->id)
            ->set('weightQty', 6)
            ->set('weightPrice', 18_000)
            ->call('confirmWeightAdd');

        $this->assertEquals(1, AuditLog::where('action', 'pos.stock_insuffisant')->count(),
            'Douze demandes sur dix disponibles : alerte attendue.');
        $this->assertCount(2, $composant->get('cart'));
    }
}
