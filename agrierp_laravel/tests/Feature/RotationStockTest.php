<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseLine;
use App\Models\StockMovement;
use App\Models\Supplier;
use App\Services\StockRotationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.47 (Sprint 14) — ROTATION DU STOCK.
 *
 * Ce qui manquait n'était pas une décision du client mais une convention de
 * valorisation. Le ticket 14.41 l'a tranchée au PMP pour l'écart d'inventaire ;
 * la même vaut ici, sans quoi le projet en aurait deux.
 *
 * Le test le plus important est le dernier : il reproduit le profil réel de
 * cette exploitation — elle PRODUIT ce qu'elle vend — et vérifie que le taux de
 * couverture le dit, plutôt que de laisser lire un ratio nu.
 */
class RotationStockTest extends TestCase
{
    use RefreshDatabase;

    private ProductCategory $categorie;

    private Supplier $fournisseur;

    protected function setUp(): void
    {
        parent::setUp();

        $this->categorie = ProductCategory::create(['label' => 'Général', 'is_active' => true]);
        $this->fournisseur = Supplier::create(['name' => 'Provenderie', 'phone' => '+22997000000', 'is_active' => true]);
    }

    private function produit(string $sku, ?float $prixAchat, float $qteAchetee = 100): Product
    {
        $produit = Product::create([
            'sku' => $sku, 'name' => 'Produit '.$sku, 'category_id' => $this->categorie->id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 1_000, 'price_max' => 2_000,
            'tva_rate' => 0, 'stock_qty' => 0, 'is_active' => true,
        ]);

        if ($prixAchat !== null) {
            $achat = Purchase::create([
                'supplier_id' => $this->fournisseur->id, 'payment_mode' => 'especes',
                'total' => $qteAchetee * $prixAchat, 'purchase_date' => '2026-05-01',
            ]);
            PurchaseLine::create([
                'purchase_id' => $achat->id, 'product_id' => $produit->id,
                'qty' => $qteAchetee, 'unit_price' => $prixAchat,
            ]);
        }

        return $produit;
    }

    private function mouvement(Product $p, float $qty, string $date, string $type, string $ref): void
    {
        StockMovement::create([
            'product_id' => $p->id, 'type' => $type, 'quantity' => $qty,
            'movement_date' => $date, 'reference_type' => $ref,
        ]);
    }

    /** La formule standard, appliquée telle quelle. */
    public function test_the_standard_formula_holds(): void
    {
        $p = $this->produit('ALI-001', 500);

        $this->mouvement($p, 100, '2026-05-20', 'entree', 'purchase');   // stock avant juin : 100 → 50 000 F
        $this->mouvement($p, 40, '2026-06-10', 'sortie', 'sale');        // COGS = 40 × 500 = 20 000

        $r = app(StockRotationService::class)->pourLeMois('2026-06');

        // Stock moyen = (50 000 au 31/05 + 30 000 au 30/06) ÷ 2 = 40 000.
        $this->assertEquals(20_000, $r['cogs']);
        $this->assertEquals(40_000, $r['stock_moyen']);
        $this->assertEquals(0.5, $r['rotation']);
    }

    /**
     * ⚠️ SEULES LES VENTES FONT LE COGS. Une casse fait baisser le stock sans
     * être une marchandise vendue : l'inclure ferait passer une exploitation
     * qui perd sa marchandise pour une exploitation qui l'écoule vite.
     */
    public function test_losses_are_not_goods_sold(): void
    {
        $p = $this->produit('ALI-001', 500);

        $this->mouvement($p, 100, '2026-05-20', 'entree', 'purchase');
        $this->mouvement($p, 40, '2026-06-10', 'sortie', 'stock_adjustment');

        $this->assertEquals(0, app(StockRotationService::class)->pourLeMois('2026-06')['cogs']);
    }

    /** ⚠️ Stock moyen nul ⇒ aucune rotation, jamais l'infini ni zéro. */
    public function test_an_empty_average_stock_yields_no_ratio(): void
    {
        $this->produit('ALI-001', 500);   // acheté mais jamais entré en stock

        $r = app(StockRotationService::class)->pourLeMois('2026-06');

        $this->assertNull($r['rotation']);
        $this->assertEquals(0, $r['stock_moyen']);
    }

    /** ⚠️ Le stock se reconstruit depuis l'historique, pas depuis `stock_qty`. */
    public function test_the_stock_value_is_rebuilt_from_history(): void
    {
        $p = $this->produit('ALI-001', 500);
        $p->update(['stock_qty' => 9_999]);   // solde de MAINTENANT, sans mouvement

        $this->mouvement($p, 100, '2026-05-20', 'entree', 'purchase');

        $this->assertEquals(50_000, app(StockRotationService::class)->pourLeMois('2026-06')['stock_moyen']);
    }

    /** ⚠️ Une quantité négative vaut zéro : un actif ne peut pas être négatif. */
    public function test_a_negative_quantity_is_valued_at_zero(): void
    {
        $p = $this->produit('ALI-001', 500);

        $this->mouvement($p, 10, '2026-05-20', 'entree', 'purchase');
        $this->mouvement($p, 30, '2026-05-25', 'sortie', 'sale');   // solde −20

        $this->assertEquals(0, app(StockRotationService::class)->pourLeMois('2026-06')['stock_moyen']);
    }

    /**
     * ⚠️⚠️ LE PROFIL RÉEL DE CETTE EXPLOITATION. Elle PRODUIT ce qu'elle vend :
     * la marchandise vendue n'a aucun coût d'achat, et le ratio ne couvre donc
     * qu'une fraction des ventes. Le taux de couverture doit le dire — un ratio
     * partiel affiché nu serait un contresens.
     */
    public function test_the_coverage_rate_exposes_a_partial_perimeter(): void
    {
        $achete = $this->produit('ALI-001', 500);
        $produitALaFerme = $this->produit('AVI-001', null);   // aucun achat : aucun PMP

        $this->mouvement($achete, 100, '2026-05-20', 'entree', 'purchase');
        $this->mouvement($achete, 10, '2026-06-10', 'sortie', 'sale');

        $this->mouvement($produitALaFerme, 200, '2026-05-20', 'entree', 'elevage');
        $this->mouvement($produitALaFerme, 30, '2026-06-11', 'sortie', 'sale');
        $this->mouvement($produitALaFerme, 25, '2026-06-12', 'sortie', 'sale');
        $this->mouvement($produitALaFerme, 20, '2026-06-13', 'sortie', 'sale');

        $r = app(StockRotationService::class)->pourLeMois('2026-06');

        $this->assertEquals(1, $r['produits_sans_pmp']);
        $this->assertEquals(25.0, $r['couverture'], 'Une vente sur quatre porte un cout connu.');
        $this->assertEquals(5_000, $r['cogs'], 'Le produit sans PMP n\'entre pas au numerateur...');
        $this->assertEquals(47_500, $r['stock_moyen'], '...ni au denominateur.');
    }

    /** Aucune vente et couverture nulle ne se disent pas pareil. */
    public function test_no_sale_at_all_is_not_a_zero_coverage(): void
    {
        $p = $this->produit('ALI-001', 500);
        $this->mouvement($p, 100, '2026-05-20', 'entree', 'purchase');

        $this->assertNull(app(StockRotationService::class)->pourLeMois('2026-06')['couverture']);
    }
}
