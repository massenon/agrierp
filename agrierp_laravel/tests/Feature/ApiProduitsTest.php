<?php

namespace Tests\Feature;

use App\Livewire\Stocks\AjouterProduit;
use App\Models\LivestockSpecies;
use App\Models\ModuleConfig;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.15 — créer et modifier un produit depuis le poste (`/sync/push`, table `products`),
 * et non-régression de la page web `AjouterProduit`, dont les règles passent dans
 * `ProductCatalogService`.
 */
class ApiProduitsTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private ProductCategory $categorie;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-stocks', 'web');
        Role::findOrCreate('magasinier', 'web')->givePermissionTo('manage-stocks');
        Role::findOrCreate('caissier', 'web');

        foreach ([['magasin', 'magasinier'], ['caisse', 'caissier']] as [$u, $r]) {
            User::create([
                'name' => ucfirst($u), 'username' => $u, 'email' => $u.'@fermeolouwachegoun.com',
                'password' => bcrypt(self::MDP), 'is_active' => true,
            ])->assignRole($r);
        }

        $this->categorie = ProductCategory::create(['label' => 'Aviculture', 'is_active' => true]);
    }

    private function avec(string $u)
    {
        $jeton = $this->postJson('/api/auth/login', [
            'identifiant' => $u, 'password' => self::MDP, 'device_name' => 'poste-'.$u,
        ])->json('token');

        return $this->withHeader('Authorization', 'Bearer '.$jeton);
    }

    private function corps(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'sku' => 'LOC-ABC123',
            'name' => 'Poulet fermier',
            'description' => 'Vif, vendu à la pièce',
            'category_id' => $this->categorie->id,
            'unit' => 'u',
            'pricing_mode' => 'fourchette',
            'price_min' => 3000,
            'price_max' => 4000,
            'tva_rate' => 0,
            'stock_qty' => 12,
            'alert_threshold' => 5,
        ], $remplace);
    }

    private function pousser(string $u, array ...$produits)
    {
        return $this->avec($u)->postJson('/api/sync/push', [
            'device_id' => 'poste-'.$u, // S-T2 : le poste du jeton (voir `avec`)
            'products' => $produits,
        ])->assertOk();
    }

    public function test_un_produit_du_poste_est_cree_avec_son_uuid_et_un_sku_du_serveur(): void
    {
        $p = $this->corps();
        $r = $this->pousser('magasin', $p);

        $this->assertSame([$p['id']], $r->json('products.accepted'));
        $cree = Product::find($p['id']);
        $this->assertNotNull($cree, "le serveur garde l'UUID du poste");
        $this->assertSame('AVI-001', $cree->sku, 'le SKU provisoire du poste est ignoré');
        $this->assertEquals(12, $cree->stock_qty);
        $this->assertTrue((bool) $cree->is_active);
        $this->assertDatabaseHas('audit_logs', ['action' => 'product.created']);
        $this->assertSame(0, $r->json('referentiels_ignored'));
    }

    public function test_le_sku_suivant_s_incremente(): void
    {
        $this->pousser('magasin', $this->corps(['name' => 'A']));
        $b = $this->corps(['name' => 'B']);
        $this->pousser('magasin', $b);

        $this->assertSame('AVI-002', Product::find($b['id'])->sku);
    }

    public function test_un_renvoi_du_meme_id_n_est_pas_un_doublon(): void
    {
        $p = $this->corps();
        $this->pousser('magasin', $p);
        $r = $this->pousser('magasin', array_merge($p, ['name' => 'Poulet label']));

        $this->assertSame([$p['id']], $r->json('products.accepted'));
        $this->assertSame(1, Product::count());
        $this->assertSame('Poulet label', Product::find($p['id'])->name);
        $this->assertSame('AVI-001', Product::find($p['id'])->sku);
    }

    public function test_une_modification_ne_touche_jamais_la_quantite_en_stock(): void
    {
        $p = $this->corps(['stock_qty' => 12]);
        $this->pousser('magasin', $p);

        $this->pousser('magasin', array_merge($p, ['stock_qty' => 9999]));

        $this->assertEquals(12, Product::find($p['id'])->stock_qty);
    }

    public function test_la_fourchette_exige_les_deux_prix_et_max_superieur_a_min(): void
    {
        $sans = $this->corps(['price_min' => null, 'price_max' => null]);
        $inverse = $this->corps(['price_min' => 4000, 'price_max' => 3000]);

        $r = $this->pousser('magasin', $sans, $inverse);

        $this->assertSame([], $r->json('products.accepted'));
        $this->assertCount(2, $r->json('products.rejected'));
        $this->assertStringContainsString(
            'Le prix maximum doit être supérieur ou égal au prix minimum.',
            $r->json('products.rejected.1.reason'),
        );
        $this->assertSame(0, Product::count());
    }

    public function test_sur_devis_n_enregistre_aucun_prix_meme_s_il_est_envoye(): void
    {
        $p = $this->corps(['pricing_mode' => 'quote', 'price_min' => 999, 'price_max' => 9999]);
        $this->pousser('magasin', $p);

        $cree = Product::find($p['id']);
        $this->assertNull($cree->price_min);
        $this->assertNull($cree->price_max);
        $this->assertSame('quote', $cree->pricing_mode);
    }

    public function test_un_mode_inconnu_ou_une_categorie_inconnue_est_refuse(): void
    {
        $r = $this->pousser(
            'magasin',
            $this->corps(['pricing_mode' => 'fixe']),
            $this->corps(['category_id' => '00000000-0000-0000-0000-000000000000']),
        );

        $this->assertCount(2, $r->json('products.rejected'));
        $this->assertSame(0, Product::count());
    }

    public function test_un_ajustement_sur_un_produit_cree_dans_le_meme_envoi_est_accepte(): void
    {
        $p = $this->corps(['stock_qty' => 10]);

        $r = $this->avec('magasin')->postJson('/api/sync/push', [
            'device_id' => 'poste-magasin', // S-T2 : le poste du jeton (voir `avec`)
            // ⚠️ L'ajustement est listé AVANT le produit : l'ordre du paquet ne compte
            // pas, le serveur traite les produits d'abord.
            'stock_adjustments' => [[
                'client_ref' => (string) Str::uuid(),
                'product_id' => $p['id'],
                'type' => 'entree',
                'quantity' => 5,
                'reference_type' => 'ajustement',
            ]],
            'products' => [$p],
        ])->assertOk();

        $this->assertSame([$p['id']], $r->json('products.accepted'));
        $this->assertSame([], $r->json('stock_adjustments.rejected'));
    }

    public function test_un_identifiant_qui_n_est_pas_un_uuid_est_refuse(): void
    {
        $r = $this->pousser('magasin', $this->corps(['id' => 'pas-un-uuid']));

        $this->assertCount(1, $r->json('products.rejected'));
        $this->assertSame(0, Product::count());
    }

    public function test_sans_droit_manage_stocks_tout_est_refuse_avec_une_raison(): void
    {
        $p = $this->corps();
        $r = $this->pousser('caisse', $p);

        $this->assertSame([], $r->json('products.accepted'));
        $this->assertSame($p['id'], $r->json('products.rejected.0.id'));
        $this->assertStringContainsString('rôle', $r->json('products.rejected.0.reason'));
        $this->assertSame(0, Product::count());
    }

    public function test_le_tirage_sert_les_especes_actives_seulement(): void
    {
        $active = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);
        LivestockSpecies::create(['code' => 'helico', 'label' => 'Escargots', 'is_enabled' => false]);
        ModuleConfig::create(['species_code' => 'cuniculture', 'is_enabled' => true]);
        ModuleConfig::create(['species_code' => 'helico', 'is_enabled' => false]);

        $especes = collect($this->avec('caisse')->getJson('/api/sync/pull')->assertOk()->json('livestock_species'));

        $this->assertSame([$active->id], $especes->pluck('id')->all());
        $this->assertSame('Lapins', $especes->first()['label']);
    }

    // ── La page web, refactorisée pour partager le service ──────────────────

    public function test_la_page_web_cree_toujours_un_produit_comme_avant(): void
    {
        $this->actingAs(User::where('username', 'magasin')->first());

        Livewire::test(AjouterProduit::class)
            ->set('name', 'Œufs de table')
            ->set('category_id', $this->categorie->id)
            ->set('unit', 'plateau')
            ->set('pricing_mode', 'fourchette')
            ->set('price_min', 2000)
            ->set('price_max', 2500)
            ->set('stock_qty', 30)
            ->set('alert_threshold', 5)
            ->call('save')
            ->assertHasNoErrors();

        $p = Product::where('name', 'Œufs de table')->first();
        $this->assertSame('AVI-001', $p->sku);
        $this->assertEquals(30, $p->stock_qty);
    }

    /**
     * 🔴→✅ Ticket S-T12 (trouvé par l'essai à plusieurs postes) — LE STOCK INITIAL ENTRE PAR LE GRAND LIVRE, au poste
     * comme au web. Il était écrit dans `stock_qty` sans mouvement : 12 au stock, 0 au grand livre, et tout ce qui
     * reconstruit le stock depuis `stock_movements` (rotation, Stock Final des fiches) se trompait de 12.
     */
    public function test_le_stock_initial_est_un_mouvement_du_grand_livre(): void
    {
        $p = $this->corps(['stock_qty' => 12]);
        $this->pousser('magasin', $p);

        $mouvement = \App\Models\StockMovement::where('product_id', $p['id'])->sole();
        $this->assertSame(['entree', 12.0, 'manual_addition', 'Stock initial'],
            [$mouvement->type, (float) $mouvement->quantity, $mouvement->reference_type, $mouvement->reason]);
        $this->assertEquals(12, Product::find($p['id'])->stock_qty, 'le stock vaut le grand livre : 12, pas 24');

        // Le renvoi (modification) n'ajoute rien ; un produit créé sans stock n'a aucun mouvement.
        $this->pousser('magasin', $p);
        $vide = $this->corps(['name' => 'Sans stock', 'stock_qty' => 0]);
        $this->pousser('magasin', $vide);
        $this->assertSame(1, \App\Models\StockMovement::count());

        $this->actingAs(User::where('username', 'magasin')->first());
        Livewire::test(AjouterProduit::class)
            ->set('name', 'Œufs de table')->set('category_id', $this->categorie->id)->set('unit', 'plateau')
            ->set('pricing_mode', 'fourchette')->set('price_min', 2000)->set('price_max', 2500)
            ->set('stock_qty', 30)->call('save')->assertHasNoErrors();
        $web = Product::where('name', 'Œufs de table')->sole();
        $this->assertEquals(30, $web->stock_qty);
        $this->assertSame(30.0, (float) \App\Models\StockMovement::where('product_id', $web->id)->sole()->quantity);
    }

    public function test_la_page_web_applique_la_meme_regle_de_fourchette(): void
    {
        $this->actingAs(User::where('username', 'magasin')->first());

        Livewire::test(AjouterProduit::class)
            ->set('name', 'X')
            ->set('category_id', $this->categorie->id)
            ->set('pricing_mode', 'fourchette')
            ->set('price_min', 5000)
            ->set('price_max', 100)
            ->call('save')
            ->assertHasErrors(['price_max']);

        $this->assertDatabaseCount('products', 0);
    }
}
