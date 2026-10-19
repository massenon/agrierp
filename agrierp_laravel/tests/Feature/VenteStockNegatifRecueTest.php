<?php

namespace Tests\Feature;

use App\Models\Notification;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Sale;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket H14 — VENTE REÇUE D'UN POSTE QUI REND UN STOCK NÉGATIF (décision D-SYNC-4 du 19/10/2026 : accepter et
 * signaler). Calcul à la main : stock 1, vente de 3 → stock −2, la vente est enregistrée, l'administrateur prévenu.
 */
class VenteStockNegatifRecueTest extends TestCase
{
    use RefreshDatabase;

    private Product $produit;

    private User $caissier;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->caissier = User::create([
            'name' => 'Caissier', 'username' => 'caisse', 'email' => 'caisse@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->caissier->assignRole('caissier');

        $categorie = ProductCategory::create(['label' => 'Œufs', 'is_active' => true]);
        $this->produit = Product::create([
            'sku' => 'OEU-001', 'name' => 'Plateau d\'œufs', 'category_id' => $categorie->id,
            'unit' => 'plateau', 'pricing_mode' => 'fourchette', 'tva_rate' => 0, 'stock_qty' => 1, 'is_active' => true,
        ]);
    }

    private function vendre(int $qte): void
    {
        $this->actingAs($this->caissier, 'sanctum')->postJson('/api/sync/push', [
            'sales' => [[
                'id' => '88888888-8888-4888-8888-88888888888'.$qte,
                'payment_mode' => 'especes', 'subtotal' => 2500 * $qte, 'total' => 2500 * $qte,
                'lines' => [[
                    'product_id' => $this->produit->id, 'qty' => $qte, 'unit_price' => 2500,
                    'manual_total_amount' => 2500 * $qte,
                ]],
            ]],
        ])->assertOk()->assertJsonPath('sales.rejected', []);
    }

    public function test_une_vente_qui_rend_le_stock_negatif_est_acceptee_et_signalee(): void
    {
        $this->vendre(3);

        $this->assertSame(1, Sale::count(), 'la vente a eu lieu : elle est enregistrée');
        $this->assertSame(-2.0, (float) $this->produit->fresh()->stock_qty);

        $alerte = Notification::where('type', 'stock_low')->sole();
        $this->assertSame(['admin', 'critique'], [$alerte->target_role, $alerte->severity]);
        $this->assertStringContainsString('Stock négatif après synchronisation', $alerte->title);
        $this->assertStringContainsString('-2', $alerte->message);
    }

    public function test_une_vente_couverte_par_le_stock_ne_signale_rien(): void
    {
        $this->vendre(1);

        $this->assertSame(0.0, (float) $this->produit->fresh()->stock_qty);
        $this->assertSame(0, Notification::count());
    }
}
