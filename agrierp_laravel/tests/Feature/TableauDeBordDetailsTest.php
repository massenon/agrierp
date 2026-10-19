<?php

namespace Tests\Feature;

use App\Livewire\Dashboard\Index;
use App\Models\FiscalYear;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket H11 (décision D-H-maquette du 19/10/2026) — LES DÉTAILS DU TABLEAU DE BORD DU POSTE EXISTENT AU WEB.
 * Caisse 40 000 + Banque 125 000 (+ un compte archivé non compté) ; 4 produits sous leur seuil, les 3 premiers par
 * nom affichés sous la carte (le 4ᵉ reste visible dans les Alertes critiques, qui en listent 5) ; exercice 2026 ouvert.
 */
class TableauDeBordDetailsTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $u = User::create(['name' => 'Admin', 'username' => 'admin', 'email' => 'dg@olouwachegoun.bj', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $u->assignRole('admin');
        $this->actingAs($u);
    }

    public function test_les_details_du_poste_sont_au_web(): void
    {
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse', 'account_code' => '571', 'balance' => 40000, 'is_active' => true]);
        TreasuryAccount::create(['type' => 'banque', 'label' => 'Banque', 'account_code' => '521', 'balance' => 125000, 'is_active' => true]);
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Ancienne caisse', 'account_code' => '5711', 'balance' => 999, 'is_active' => false]);
        $cat = ProductCategory::create(['label' => 'Intrants', 'is_active' => true]);
        foreach (['Vermifuge', 'Anti-coccidien', 'Aliment lapin', 'Vitamines'] as $i => $nom) {
            Product::create(['sku' => "P-$i", 'name' => $nom, 'category_id' => $cat->id, 'unit' => 'u', 'pricing_mode' => 'fourchette',
                'tva_rate' => 0, 'stock_qty' => 1, 'alert_threshold' => 5, 'is_active' => true]);
        }
        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);

        Livewire::test(Index::class)
            ->assertSee('Caisse : 40 000 F · Banque : 125 000 F')
            ->assertSee('Aliment lapin, Anti-coccidien, Vermifuge')
            ->assertSee('Exercice 2026 actif');
    }

    public function test_sans_exercice_ouvert_l_en_tete_le_dit(): void
    {
        Livewire::test(Index::class)->assertSee('Aucun exercice ouvert')->assertSee('Aucun produit sous son seuil');
    }
}
