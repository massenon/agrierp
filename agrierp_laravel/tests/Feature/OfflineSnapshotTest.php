<?php

namespace Tests\Feature;

use App\Models\Customer;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Receivable;
use App\Models\Sale;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * PWA-4 — Snapshot hors ligne : stock, créances, ventes récentes (11/11/2026)
 *
 * Vérifie que GET /api/offline/snapshot :
 *  - exige une authentification ;
 *  - retourne les bonnes clés JSON ;
 *  - filtre selon les droits (`view-stocks` / `view-ventes`) ;
 *  - retourne chaque produit avec les colonnes attendues (id, name, stock_qty, alert_threshold, unit) ;
 *  - ne retourne que les créances actives (solde > 0) ;
 *  - ne retourne que les 30 dernières ventes non annulées.
 */
class OfflineSnapshotTest extends TestCase
{
    use RefreshDatabase;

    private const URL = '/api/offline/snapshot';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
    }

    // --- Helpers ---

    private function compte(string $role): User
    {
        $u = User::create([
            'name'      => ucfirst($role),
            'username'  => $role . '_snap',
            'email'     => $role . '_snap@fermeolouwachegoun.com',
            'password'  => bcrypt('LogiAgriERP@2026'),
            'is_active' => true,
        ]);
        $u->assignRole($role);
        return $u;
    }

    private function categorie(): ProductCategory
    {
        static $c = 0;
        $c++;
        return ProductCategory::create(['label' => 'Catégorie test ' . $c, 'is_active' => true]);
    }

    private function produit(array $surcharge = []): Product
    {
        static $n = 0;
        $n++;
        return Product::create(array_merge([
            'name'            => 'Aliment Poulet',
            'sku'             => 'TEST-' . $n,
            'category_id'     => $this->categorie()->id,
            'unit'            => 'sac',
            'stock_qty'       => 10,
            'alert_threshold' => 5,
            'is_active'       => true,
            'pricing_mode'    => 'quote',
        ], $surcharge));
    }

    private function client(): Customer
    {
        return Customer::create([
            'name'      => 'Ferme Exemple',
            'is_active' => true,
        ]);
    }

    private function creance(Customer $client, array $surcharge = []): Receivable
    {
        return Receivable::create(array_merge([
            'customer_id' => $client->id,
            'amount'      => 50000,
            'amount_paid' => 0,
            'due_date'    => now()->addDays(30)->toDateString(),
            'status'      => 'en_cours',
        ], $surcharge));
    }

    private function vente(array $surcharge = []): Sale
    {
        return Sale::create(array_merge([
            'payment_mode' => 'especes',
            'status'       => 'validee',
            'subtotal'     => 25000,
            'discount'     => 0,
            'total'        => 25000,
            'sold_at'      => now(),
        ], $surcharge));
    }

    // --- Tests ---

    /** L'accès sans authentification retourne 401. */
    public function test_sans_authentification_retourne_401(): void
    {
        $this->getJson(self::URL)->assertUnauthorized();
    }

    /** La structure JSON contient les quatre clés attendues. */
    public function test_structure_json_complete(): void
    {
        $admin = $this->compte('admin');

        $this->actingAs($admin, 'sanctum')
            ->getJson(self::URL)
            ->assertOk()
            ->assertJsonStructure(['stock', 'creances', 'ventes_recentes', 'cached_at']);
    }

    /** `cached_at` est une chaîne ISO 8601 non vide. */
    public function test_cached_at_est_iso8601(): void
    {
        $admin = $this->compte('admin');

        $reponse = $this->actingAs($admin, 'sanctum')
            ->getJson(self::URL)
            ->assertOk();

        $cachedAt = $reponse->json('cached_at');
        $this->assertNotEmpty($cachedAt);
        // Doit être parsable comme date
        $this->assertNotFalse(strtotime($cachedAt), 'cached_at doit être une date valide');
    }

    /** Chaque produit retourné possède les colonnes attendues. */
    public function test_chaque_produit_a_les_colonnes_attendues(): void
    {
        $admin = $this->compte('admin');
        $this->produit();

        $reponse = $this->actingAs($admin, 'sanctum')
            ->getJson(self::URL)
            ->assertOk();

        $produits = $reponse->json('stock');
        $this->assertNotEmpty($produits);
        foreach ($produits as $p) {
            $this->assertArrayHasKey('id', $p);
            $this->assertArrayHasKey('name', $p);
            $this->assertArrayHasKey('stock_qty', $p);
            $this->assertArrayHasKey('alert_threshold', $p);
            $this->assertArrayHasKey('unit', $p);
        }
    }

    /** Seuls les produits actifs sont retournés. */
    public function test_seuls_les_produits_actifs_sont_retournes(): void
    {
        $admin = $this->compte('admin');
        $actif   = $this->produit(['name' => 'Produit actif',   'is_active' => true]);
        $inactif = $this->produit(['name' => 'Produit inactif', 'is_active' => false]);

        $reponse = $this->actingAs($admin, 'sanctum')
            ->getJson(self::URL)
            ->assertOk();

        $noms = collect($reponse->json('stock'))->pluck('name');
        $this->assertContains('Produit actif', $noms->all());
        $this->assertNotContains('Produit inactif', $noms->all());
    }

    /** Un compte sans `view-stocks` reçoit un tableau `stock` vide. */
    public function test_sans_droit_view_stocks_stock_est_vide(): void
    {
        // Le rôle `animalier` n'a pas `view-stocks`
        $animalier = $this->compte('animalier');
        $this->produit();

        $reponse = $this->actingAs($animalier, 'sanctum')
            ->getJson(self::URL)
            ->assertOk();

        $this->assertEmpty($reponse->json('stock'));
    }

    /** Un compte sans `view-ventes` reçoit des tableaux créances et ventes vides. */
    public function test_sans_droit_view_ventes_creances_et_ventes_sont_vides(): void
    {
        // Le rôle `animalier` n'a pas `view-ventes`
        $animalier = $this->compte('animalier');
        $client    = $this->client();
        $this->creance($client);
        $this->vente();

        $reponse = $this->actingAs($animalier, 'sanctum')
            ->getJson(self::URL)
            ->assertOk();

        $this->assertEmpty($reponse->json('creances'));
        $this->assertEmpty($reponse->json('ventes_recentes'));
    }

    /** Les créances soldées (amount_paid = amount) ne sont pas retournées. */
    public function test_creances_soldees_exclues(): void
    {
        $admin  = $this->compte('admin');
        $client = $this->client();
        $this->creance($client, ['amount' => 10000, 'amount_paid' => 10000, 'status' => 'soldee']);

        $reponse = $this->actingAs($admin, 'sanctum')
            ->getJson(self::URL)
            ->assertOk();

        $this->assertEmpty($reponse->json('creances'));
    }

    /** Chaque créance retournée a les colonnes attendues. */
    public function test_chaque_creance_a_les_colonnes_attendues(): void
    {
        $admin  = $this->compte('admin');
        $client = $this->client();
        $this->creance($client);

        $reponse = $this->actingAs($admin, 'sanctum')
            ->getJson(self::URL)
            ->assertOk();

        $creances = $reponse->json('creances');
        $this->assertNotEmpty($creances);
        foreach ($creances as $c) {
            $this->assertArrayHasKey('id', $c);
            $this->assertArrayHasKey('customer_name', $c);
            $this->assertArrayHasKey('amount_due', $c);
            $this->assertArrayHasKey('due_date', $c);
        }
    }

    /** `amount_due` est le solde résiduel (amount − amount_paid). */
    public function test_amount_due_est_le_solde_residuel(): void
    {
        $admin  = $this->compte('admin');
        $client = $this->client();
        $this->creance($client, ['amount' => 50000, 'amount_paid' => 20000]);

        $reponse = $this->actingAs($admin, 'sanctum')
            ->getJson(self::URL)
            ->assertOk();

        $creances = $reponse->json('creances');
        $this->assertNotEmpty($creances);
        $this->assertEquals(30000.0, $creances[0]['amount_due']);
    }

    /** Les ventes récentes sont au plus 30 et toutes non annulées. */
    public function test_au_plus_30_ventes_non_annulees(): void
    {
        $admin = $this->compte('admin');
        // 35 ventes valides + 2 annulées
        for ($i = 0; $i < 35; $i++) {
            $this->vente(['sold_at' => now()->subMinutes($i)]);
        }
        $this->vente(['status' => 'annulee']);
        $this->vente(['status' => 'annulee']);

        $reponse = $this->actingAs($admin, 'sanctum')
            ->getJson(self::URL)
            ->assertOk();

        $ventes = $reponse->json('ventes_recentes');
        $this->assertLessThanOrEqual(30, count($ventes));
        foreach ($ventes as $v) {
            // Aucune vente annulée ne doit figurer
            $this->assertNotEquals('annulee', $v['status'] ?? null);
        }
    }

    /** Chaque vente retournée a les colonnes attendues. */
    public function test_chaque_vente_a_les_colonnes_attendues(): void
    {
        $admin = $this->compte('admin');
        $this->vente();

        $reponse = $this->actingAs($admin, 'sanctum')
            ->getJson(self::URL)
            ->assertOk();

        $ventes = $reponse->json('ventes_recentes');
        $this->assertNotEmpty($ventes);
        foreach ($ventes as $v) {
            $this->assertArrayHasKey('id', $v);
            $this->assertArrayHasKey('sold_at', $v);
            $this->assertArrayHasKey('total', $v);
            $this->assertArrayHasKey('payment_mode', $v);
        }
    }
}
