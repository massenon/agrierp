<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\SyncController;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Curseur du tirage — défaut relevé en comparant la méthode de synchronisation du projet TATACORA (« horizon »).
 *
 * `server_time` était calculé APRÈS toutes les requêtes du tirage : une ligne écrite au web PENDANT le tirage,
 * après la lecture de sa table, portait un `updated_at` antérieur au curseur rendu. Ni ce tirage ni le suivant
 * ne la servaient : elle n'arrivait jamais au poste, sans aucune erreur. Le curseur est désormais l'instant du
 * DÉBUT du tirage, reculé de `HORIZON_TIRAGE_SECONDES`.
 */
class SyncCurseurTirageTest extends TestCase
{
    use RefreshDatabase;

    private ProductCategory $categorie;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $utilisateur = User::create([
            'name' => 'Administrateur', 'username' => 'admin', 'email' => 'dg@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $utilisateur->assignRole('admin');
        Sanctum::actingAs($utilisateur);
        $this->categorie = ProductCategory::create(['label' => 'Intrants', 'is_active' => true]);
    }

    private function produit(string $sku): Product
    {
        return Product::create([
            'sku' => $sku, 'name' => 'Produit '.$sku, 'category_id' => $this->categorie->id, 'unit' => 'u',
            'pricing_mode' => 'fourchette', 'price_min' => 100, 'price_max' => 200, 'stock_qty' => 1, 'is_active' => true,
        ]);
    }

    public function test_le_curseur_est_l_instant_du_debut_recule_de_l_horizon(): void
    {
        Carbon::setTestNow('2026-10-19 10:00:00');

        $curseur = $this->getJson('/api/sync/pull')->assertOk()->json('server_time');

        $this->assertSame(
            Carbon::parse('2026-10-19 10:00:00')->subSeconds(SyncController::HORIZON_TIRAGE_SECONDES)->toIso8601String(),
            $curseur,
        );
    }

    public function test_une_ligne_ecrite_pendant_le_tirage_est_servie_au_tirage_suivant(): void
    {
        Carbon::setTestNow('2026-10-19 10:00:00');
        $curseur = $this->getJson('/api/sync/pull')->assertOk()->json('server_time');

        // Écrite à la même seconde que le tirage, après la lecture de `products` : le tirage ne l'a pas vue.
        $pendant = $this->produit('PENDANT');

        Carbon::setTestNow('2026-10-19 10:15:00');
        $ids = collect($this->getJson('/api/sync/pull?since='.urlencode($curseur))->assertOk()->json('products'))
            ->pluck('id');

        $this->assertContains($pendant->id, $ids->all(), 'la ligne écrite pendant le tirage serait perdue pour le poste');
    }

    public function test_une_ligne_deja_servie_peut_revenir_sans_dommage(): void
    {
        Carbon::setTestNow('2026-10-19 09:59:58');
        $avant = $this->produit('AVANT');

        Carbon::setTestNow('2026-10-19 10:00:00');
        $premier = $this->getJson('/api/sync/pull')->assertOk();
        $this->assertContains($avant->id, collect($premier->json('products'))->pluck('id')->all());

        // Dans l'horizon : resservie au tirage suivant (le poste fait une insertion-ou-mise-à-jour).
        Carbon::setTestNow('2026-10-19 10:15:00');
        $suivant = $this->getJson('/api/sync/pull?since='.urlencode($premier->json('server_time')))->assertOk();
        $this->assertContains($avant->id, collect($suivant->json('products'))->pluck('id')->all());
    }
}
