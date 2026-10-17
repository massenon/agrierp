<?php

namespace Tests\Feature;

use App\Livewire\Ventes\PosInterface;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.2 — 2e occurrence RÉELLE du défaut de propriété calculée périmée
 * corrigé sur `ClotureExercice`, trouvée par recherche systématique du motif
 * dans les 81 composants Livewire (et non au hasard d'une découverte).
 *
 * `PosInterface::validateSale()` lit `$this->subtotal` / `$this->total` /
 * `$this->changeDue` — mémoïsés par Livewire pour la durée de la requête —
 * puis vide le panier (`$this->cart = []`). Sans invalidation, le rendu qui
 * suit réaffiche le total de la vente **déjà encaissée** au-dessus d'un
 * panier vide : la caissière voit un montant qui ne correspond plus à rien.
 * Écran le plus utilisé du système (Document 01 §6.7, priorité urgente).
 */
class PosInterfaceStaleTotalsTest extends TestCase
{
    use RefreshDatabase;

    private function actingAsCashier(): User
    {
        foreach (['view-ventes', 'manage-ventes'] as $name) {
            Permission::findOrCreate($name, 'web');
        }
        $role = Role::findOrCreate('caissier', 'web');
        $role->givePermissionTo(['view-ventes', 'manage-ventes']);

        $user = User::create([
            'name' => 'Caissière Test',
            'email' => 'caisse.test@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'),
        ]);
        $user->assignRole($role);

        $this->actingAs($user);

        return $user;
    }

    private function product(): Product
    {
        $category = ProductCategory::create(['label' => 'Volailles', 'is_active' => true]);

        return Product::create([
            'sku' => 'POU-001',
            'name' => 'Poulet de chair',
            'category_id' => $category->id,
            'unit' => 'pièce',
            'pricing_mode' => 'fourchette',
            'price_min' => 2000,
            'price_max' => 3500,
            'stock_qty' => 50,
            'is_active' => true,
        ]);
    }

    public function test_totals_are_recomputed_after_the_cart_is_emptied_by_a_sale(): void
    {
        $this->actingAsCashier();

        FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);

        $product = $this->product();

        $component = Livewire::test(PosInterface::class)
            ->set('cart', [[
                'product_id' => $product->id,
                'name' => $product->name,
                'unit' => $product->unit,
                'lot_code' => null,
                'qty' => 2,
                'montant' => 6000.0,
            ]])
            ->set('paymentMode', 'especes')
            ->set('cashReceived', 10000);

        // Avant la vente : les totaux reflètent le panier.
        $this->assertEquals(6000.0, $component->instance()->subtotal);
        $this->assertEquals(6000.0, $component->instance()->total);
        $this->assertEquals(4000.0, $component->instance()->changeDue);

        $component->call('validateSale');

        // La vente est bien enregistrée et le panier vidé…
        $this->assertDatabaseCount('sales', 1);
        $this->assertSame([], $component->instance()->cart);

        // …donc les totaux réaffichés doivent suivre le panier réel, pas
        // rester figés sur la vente précédente.
        $this->assertEquals(0.0, $component->instance()->subtotal, 'Le sous-total doit suivre le panier vidé.');
        $this->assertEquals(0.0, $component->instance()->total, 'Le total doit suivre le panier vidé.');
        $this->assertEquals(0.0, $component->instance()->changeDue, 'La monnaie à rendre doit suivre le panier vidé.');
    }
}
