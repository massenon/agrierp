<?php

namespace Tests\Feature;

use App\Livewire\Parametres\PostesAppairage;
use App\Models\ChartOfAccount;
use App\Models\CompanySetting;
use App\Models\FiscalYear;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Sale;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\JournalSynchronisationService;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Auth;
use Laravel\Sanctum\PersonalAccessToken;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * PWA-1 (décision du client, 08/11/2026) — LA CAISSE HORS LIGNE DU NAVIGATEUR, côté serveur.
 *
 * Le navigateur est un POSTE de plus : jeton Sanctum nommé `pwa-<uuid>` (POST /api/auth/login), puis le protocole de
 * synchronisation EXISTANT (`/api/sync/pull|push`) — aucune route nouvelle. Ces tests prouvent que le serveur reste
 * l'autorité : il rejoue la vente venue du navigateur comme celle d'un poste (idempotence par UUID, refus motivés),
 * qu'un jeton révoqué reçoit 401, et qu'aucune réponse authentifiée n'est servie avec un cache.
 */
class PwaHorsLigneTest extends TestCase
{
    use RefreshDatabase;

    private const SALE = 'c1111111-1111-4111-8111-111111111111';

    private const APPAREIL = 'pwa-0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

    private Product $produit;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);

        FiscalYear::create(['year' => now()->year, 'start_date' => now()->startOfYear()->format('Y-m-d'), 'end_date' => now()->endOfYear()->format('Y-m-d'), 'status' => 'ouvert']);
        foreach ([['531', 'Caisse', 5], ['411', 'Clients', 4], ['443', 'TVA facturée', 4], ['701', 'Ventes de produits', 7]] as [$c, $l, $k]) {
            ChartOfAccount::create(['code' => $c, 'label' => $l, 'class' => $k, 'is_active' => true]);
        }
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);
        $cat = ProductCategory::create(['label' => 'Œufs', 'is_active' => true]);
        $this->produit = Product::create(['sku' => 'OEUF', 'name' => "Plaquette d'œufs", 'category_id' => $cat->id, 'unit' => 'plaquette',
            'pricing_mode' => 'fourchette', 'price_min' => 2000, 'price_max' => 6000, 'tva_rate' => 18, 'stock_qty' => 100, 'is_active' => true]);
        CompanySetting::current()->update(['company_name' => 'Ferme', 'ifu' => '3202601234567']);
    }

    private function compte(string $role, string $nom = null): User
    {
        $u = User::create(['name' => ucfirst($role), 'username' => $nom ?? $role, 'email' => ($nom ?? $role).'@fermeolouwachegoun.com',
            'password' => bcrypt('LogiAgriERP@2026'), 'is_active' => true]);
        $u->assignRole($role);

        return $u;
    }

    /** Appairage du navigateur : exactement l'appel que fait `appairage.js`. */
    private function appairer(string $appareil = self::APPAREIL, string $identifiant = 'caissier'): string
    {
        $r = $this->postJson('/api/auth/login', ['identifiant' => $identifiant, 'password' => 'LogiAgriERP@2026', 'device_name' => $appareil]);
        $r->assertOk()->assertJsonStructure(['token', 'user' => ['id', 'name', 'username', 'role'], 'must_change_password']);

        return $r->json('token');
    }

    /** Un nouvel appel d'API sans l'état d'authentification des appels précédents. */
    private function api(?string $jeton)
    {
        Auth::forgetGuards();
        $this->flushHeaders();

        return $jeton === null ? $this->withHeaders([]) : $this->withToken($jeton);
    }

    /** La vente telle que `construireVente()` (calculs-caisse.js) l'écrit. */
    private function venteDuNavigateur(array $plus = []): array
    {
        return array_merge([
            'id' => self::SALE, 'device_id' => self::APPAREIL, 'sync_status' => 'pending',
            'customer_id' => null, 'payment_mode' => 'especes', 'subtotal' => 11800, 'discount' => 0, 'total' => 11800,
            'cash_received' => 15000, 'change_due' => 3200, 'status' => 'validee',
            'sold_at' => now()->subMinutes(5)->toIso8601String(), 'updated_at' => now()->subMinutes(5)->toIso8601String(),
            'facture_type' => 'simple', 'client_ifu' => null, 'client_nom_facture' => null, 'aib_taux' => null,
            'lines' => [['product_id' => $this->produit->id, 'lot_id' => null, 'qty' => 2, 'unit_price' => 5900, 'manual_total_amount' => 11800]],
        ], $plus);
    }

    // ═══ Page d'activation ═══

    public function test_la_page_d_activation_exige_la_connexion_et_le_droit_d_encaisser_ou_de_tenir_les_fiches(): void
    {
        $this->get('/mode-hors-ligne')->assertRedirect('/login');

        // CAISSE-1 (volet animalier) : le comptable (view-ventes seulement) reste refusé ; l'animalier est admis (voir ModeHorsLigneAnimalierTest).
        $this->actingAs($this->compte('comptable'))->get('/mode-hors-ligne')->assertForbidden();

        $page = $this->actingAs($this->compte('caissier'))->get('/mode-hors-ligne');
        $page->assertOk()->assertSee('Mode hors ligne')->assertSee('Activer le mode hors ligne')->assertSee('modeHorsLigne(', false);
    }

    public function test_le_mot_de_passe_ne_passe_jamais_par_livewire_ni_par_le_serveur_de_la_page(): void
    {
        $vue = file_get_contents(resource_path('views/livewire/profil/mode-hors-ligne.blade.php'));
        $this->assertStringNotContainsString('wire:model', $vue, 'aucun champ de cette page n\'est lié à Livewire');
        $this->assertStringContainsString('wire:ignore', $vue);
        $this->assertStringNotContainsString('localStorage', $vue);

        $composant = file_get_contents(app_path('Livewire/Profil/ModeHorsLigne.php'));
        $this->assertDoesNotMatchRegularExpression('/public\s+(string|\?string)\s+\$(password|mot|pin)/i', $composant);
    }

    public function test_l_entree_de_menu_n_est_proposee_qu_a_qui_encaisse_ou_tient_les_fiches(): void
    {
        $this->actingAs($this->compte('caissier'))->get('/dashboard')->assertSee('href="/mode-hors-ligne"', false);
        $this->actingAs($this->compte('comptable'))->get('/dashboard')->assertDontSee('href="/mode-hors-ligne"', false);
    }

    // ═══ Appairage : un poste de plus ═══

    public function test_l_appairage_cree_un_jeton_nomme_pwa_et_un_seul_par_navigateur(): void
    {
        $this->compte('caissier');
        $premier = $this->appairer();
        $second = $this->appairer();                                  // réactivation du MÊME navigateur : même nom

        $this->assertNotSame($premier, $second);
        $jetons = PersonalAccessToken::query()->where('name', self::APPAREIL)->get();
        $this->assertCount(1, $jetons, 'un seul jeton par navigateur : le second remplace le premier');
        $this->assertStringStartsWith('pwa-', $jetons->first()->name);
        $this->assertSame(60 * 24 * 90, (int) config('sanctum.expiration'), 'les jetons expirent sous 90 jours (ticket S3)');

        $this->api($premier)->getJson('/api/auth/me')->assertUnauthorized();
        $this->api($second)->getJson('/api/auth/me')->assertOk()->assertJsonPath('username', 'caissier');
    }

    public function test_un_mot_de_passe_faux_n_en_cree_aucun(): void
    {
        $this->compte('caissier');
        $this->postJson('/api/auth/login', ['identifiant' => 'caissier', 'password' => 'faux', 'device_name' => self::APPAREIL])->assertStatus(422);
        $this->assertSame(0, PersonalAccessToken::query()->count());
    }

    public function test_le_navigateur_apparait_dans_les_postes_et_l_administrateur_peut_le_revoquer(): void
    {
        $this->compte('caissier');
        $jeton = $this->appairer();
        $admin = $this->compte('admin');

        $postes = app(JournalSynchronisationService::class)->etatDesPostes();
        $this->assertTrue($postes->contains(fn ($p) => $p['poste'] === self::APPAREIL), 'le navigateur est un poste de la supervision');

        $this->actingAs($admin);
        Livewire::test(PostesAppairage::class)->call('revoquer', self::APPAREIL)->assertDispatched('toast');
        $this->assertSame(0, PersonalAccessToken::query()->where('name', self::APPAREIL)->count());

        $this->api($jeton)->getJson('/api/sync/pull?page=1')->assertUnauthorized();
        $this->api($jeton)->postJson('/api/sync/push', ['device_id' => self::APPAREIL, 'sales' => [$this->venteDuNavigateur()]])->assertUnauthorized();
        $this->assertSame(0, Sale::query()->count(), 'une vente envoyée avec un jeton révoqué n\'entre pas');
    }

    // ═══ Tirage et envoi : le protocole du poste ═══

    public function test_le_tirage_pagine_sert_ce_que_la_caisse_copie_et_rien_de_secret(): void
    {
        $this->compte('caissier');
        $jeton = $this->appairer();

        $r = $this->api($jeton)->getJson('/api/sync/pull?page=1')->assertOk();
        $r->assertJsonStructure(['server_time', 'tables_servies', 'products', 'product_categories', 'customers', 'company_settings' => ['mecef_actif'], 'page_suivante']);
        $this->assertContains('products', $r->json('tables_servies'));
        $this->assertSame($this->produit->id, collect($r->json('products'))->firstWhere('sku', 'OEUF')['id']);
        $this->assertArrayNotHasKey('mecef_jeton_encrypted', $r->json('company_settings'), 'le jeton MeCeF ne descend jamais');
    }

    public function test_l_envoi_d_une_vente_du_navigateur_est_idempotent_par_uuid(): void
    {
        $this->compte('caissier');
        $jeton = $this->appairer();
        $corps = ['device_id' => self::APPAREIL, 'sales' => [$this->venteDuNavigateur()]];

        $premier = $this->api($jeton)->postJson('/api/sync/push', $corps)->assertOk();
        $this->assertSame([self::SALE], $premier->json('sales.accepted'));
        $this->assertSame([], $premier->json('sales.rejected'));

        // La réponse s'est perdue : le navigateur renvoie la MÊME vente. Le serveur l'acquitte, sans rien rejouer.
        $second = $this->api($jeton)->postJson('/api/sync/push', $corps)->assertOk();
        $this->assertSame([self::SALE], $second->json('sales.accepted'), 'renvoyer une vente connue n\'est pas une erreur');
        $this->assertSame([], $second->json('sales.rejected'));

        $this->assertSame(1, Sale::query()->count(), 'UNE vente par UUID');
        $vente = Sale::findOrFail(self::SALE);
        $this->assertSame(11800.0, (float) $vente->total);
        $this->assertSame('simple', $vente->facture_type);
        $this->assertSame(98.0, (float) $this->produit->fresh()->stock_qty, 'le stock est décrémenté UNE fois, par le serveur');
        $this->assertSame(1, \App\Models\AccountingEntry::query()->where('source_type', 'sale')->where('source_id', self::SALE)->count());
    }

    public function test_une_vente_normalisee_hors_ligne_part_en_attente_de_normalisation(): void
    {
        config(['mecef.actif' => true]);
        $this->compte('caissier');
        $jeton = $this->appairer();

        $vente = $this->venteDuNavigateur(['facture_type' => 'normalisee', 'client_nom_facture' => 'KPOGNON Séraphin', 'client_ifu' => '1234567890123', 'aib_taux' => '1%']);
        $this->api($jeton)->postJson('/api/sync/push', ['device_id' => self::APPAREIL, 'sales' => [$vente]])->assertOk();

        $enBase = Sale::findOrFail(self::SALE);
        $this->assertSame('normalisee', $enBase->facture_type);
        $this->assertSame('KPOGNON Séraphin', $enBase->client_nom_facture);
        $this->assertSame('1234567890123', $enBase->client_ifu);
        $this->assertSame('1%', $enBase->aib_taux);
    }

    public function test_le_serveur_revalide_le_choix_de_facture_du_navigateur(): void
    {
        $this->compte('caissier');
        $jeton = $this->appairer();

        $r = $this->api($jeton)->postJson('/api/sync/push', ['device_id' => self::APPAREIL, 'sales' => [
            $this->venteDuNavigateur(['facture_type' => 'normalisee', 'client_nom_facture' => '', 'aib_taux' => '5%']),
        ]])->assertOk();

        $this->assertSame([], $r->json('sales.accepted'));
        $this->assertStringContainsString('Le nom et prénom du client sont obligatoires pour une facture normalisée.', $r->json('sales.rejected.0.reason'));
        $this->assertSame(0, Sale::query()->count());
        $this->assertSame(100.0, (float) $this->produit->fresh()->stock_qty, 'un refus n\'écrit rien');
    }

    public function test_un_refus_est_motive_en_francais_et_ne_casse_pas_le_stock(): void
    {
        $this->compte('caissier');
        $jeton = $this->appairer();
        $inconnue = $this->venteDuNavigateur(['id' => 'c2222222-2222-4222-8222-222222222222', 'customer_id' => 'c3333333-3333-4333-8333-333333333333', 'payment_mode' => 'credit']);

        $r = $this->api($jeton)->postJson('/api/sync/push', ['device_id' => self::APPAREIL, 'sales' => [$inconnue, $this->venteDuNavigateur()]])->assertOk();

        $this->assertSame([self::SALE], $r->json('sales.accepted'), 'les autres ventes du lot partent');
        $this->assertSame('c2222222-2222-4222-8222-222222222222', $r->json('sales.rejected.0.id'));
        $this->assertStringContainsString('Client inconnu du serveur', $r->json('sales.rejected.0.reason'));
        $this->assertSame(98.0, (float) $this->produit->fresh()->stock_qty);
    }

    public function test_un_poste_ne_signe_pas_au_nom_d_un_autre_et_sans_jeton_c_est_401(): void
    {
        $this->compte('caissier');
        $jeton = $this->appairer();

        $this->api($jeton)->postJson('/api/sync/push', ['device_id' => 'pwa-autre-navigateur', 'sales' => [$this->venteDuNavigateur()]])->assertForbidden();
        $this->assertSame(0, Sale::query()->count());

        $this->api(null)->postJson('/api/sync/push', ['device_id' => self::APPAREIL, 'sales' => [$this->venteDuNavigateur()]])->assertUnauthorized();
        $this->api(null)->getJson('/api/sync/pull?page=1')->assertUnauthorized();
    }

    // ═══ Aucun HTML authentifié ni JSON servi avec un cache ═══

    public function test_aucune_reponse_authentifiee_n_est_servie_avec_un_cache(): void
    {
        $caissier = $this->compte('caissier');

        foreach (['/dashboard', '/mode-hors-ligne', '/mon-profil'] as $chemin) {
            $cache = (string) $this->actingAs($caissier)->get($chemin)->assertOk()->headers->get('Cache-Control');
            $this->assertStringNotContainsString('public', $cache, "$chemin ne doit jamais être cacheable");
            $this->assertDoesNotMatchRegularExpression('/max-age=[1-9]/', $cache, "$chemin : aucun max-age");
            $this->assertMatchesRegularExpression('/no-cache|no-store|private/', $cache, $chemin);
        }

        $jeton = $this->appairer();
        $cache = (string) $this->api($jeton)->getJson('/api/sync/pull?page=1')->assertOk()->headers->get('Cache-Control');
        $this->assertStringNotContainsString('public', $cache);
        $this->assertDoesNotMatchRegularExpression('/max-age=[1-9]/', $cache);
    }
}
