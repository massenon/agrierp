<?php

namespace Tests\Feature;

use App\Actions\AdjustStockAction;
use App\Livewire\Stocks\GestionStocks;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseLine;
use App\Models\Supplier;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket U8 — L'INVENTAIRE SAISI AU POSTE COMPTE AUX « ÉCARTS D'INVENTAIRE » DE LA GESTION DES STOCKS.
 *
 * Le poste envoie ses écarts d'inventaire (`stock_adjustments`) avec `reference_type = 'inventaire'` : le serveur les
 * rejoue par `AdjustStockAction` et passe la perte en charge comme ceux de cet écran. La carte ne lisait pourtant
 * que `adjustment` (les ajustements saisis au web) : un manquant constaté hors ligne n'y apparaissait jamais, quand
 * le poste, lui, le valorise désormais au PMP (formule du web).
 *
 * Valeurs attendues calculées à la main : PMP = (10 × 6 000 + 30 × 7 000) ÷ 40 = 6 750.
 */
class EcartsInventairePosteTest extends TestCase
{
    use RefreshDatabase;

    private Product $produit;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-19 14:00:00');

        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        $this->produit = Product::create([
            'sku' => 'ALI-001', 'name' => 'Aliment ponte 25kg', 'category_id' => $categorie->id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'price_min' => 6_500, 'price_max' => 7_500,
            'stock_qty' => 40, 'is_active' => true,
        ]);
        $fournisseur = Supplier::create(['name' => 'Provenderie', 'is_active' => true]);
        $achat = Purchase::create([
            'supplier_id' => $fournisseur->id, 'payment_mode' => 'especes',
            'total' => 270_000, 'purchase_date' => '2026-10-01',
        ]);
        foreach ([[10, 6_000], [30, 7_000]] as [$qte, $prix]) {
            PurchaseLine::create([
                'purchase_id' => $achat->id, 'product_id' => $this->produit->id, 'qty' => $qte, 'unit_price' => $prix,
            ]);
        }
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function mouvement(float $delta, string $type, string $date): void
    {
        app(AdjustStockAction::class)->execute($this->produit->fresh(), $delta, $type, null, Carbon::parse($date));
    }

    public function test_un_manquant_saisi_au_poste_compte_aux_ecarts_du_mois(): void
    {
        $this->mouvement(-3, 'inventaire', '2026-10-12 09:00:00');   // poste : −3 × 6 750 = −20 250

        $this->assertSame(-20_250.0, (float) (new GestionStocks())->kpis['ecarts']);
    }

    public function test_ecarts_du_web_et_du_poste_s_additionnent_ventes_et_autres_mois_exclus(): void
    {
        $this->mouvement(-3, 'inventaire', '2026-10-12 09:00:00');   // −20 250
        $this->mouvement(2, 'adjustment', '2026-10-15 10:00:00');    // +13 500 (écran web)
        $this->mouvement(-5, 'sale', '2026-10-16 10:00:00');         // une vente n'est pas un écart
        $this->mouvement(-1, 'inventaire', '2026-09-30 18:00:00');   // mois précédent

        // −20 250 + 13 500 = −6 750
        $this->assertSame(-6_750.0, (float) (new GestionStocks())->kpis['ecarts']);
    }
}
