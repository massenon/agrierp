<?php

namespace Tests\Feature;

use App\Livewire\Profil\ModeHorsLigne;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\TreasuryAccount;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Laravel\Sanctum\PersonalAccessToken;
use Tests\TestCase;

/**
 * CAISSE-1, volet animalier (décision du client, 09/11/2026) : « un animalier seul DOIT pouvoir activer le mode hors ligne et saisir ses fiches ».
 * Gate UNIQUE `utiliser-mode-hors-ligne` = `manage-ventes` OU `manage-elevage` ; aucun autre rôle élargi ; le serveur reste le juge des envois et des tirages.
 */
class ModeHorsLigneAnimalierTest extends TestCase
{
    use RefreshDatabase;

    private const APPAREIL = 'pwa-0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
        FiscalYear::create(['year' => now()->year, 'start_date' => now()->startOfYear()->format('Y-m-d'), 'end_date' => now()->endOfYear()->format('Y-m-d'), 'status' => 'ouvert']);
        foreach ([['531', 'Caisse', 5], ['411', 'Clients', 4], ['443', 'TVA facturée', 4], ['701', 'Ventes de produits', 7]] as [$c, $l, $k]) {
            ChartOfAccount::create(['code' => $c, 'label' => $l, 'class' => $k, 'is_active' => true]);
        }
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);
    }

    private function compte(string $role): User
    {
        $u = User::create(['name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com', 'password' => bcrypt('LogiAgriERP@2026'), 'is_active' => true]);
        $u->assignRole($role);

        return $u;
    }

    private function jeton(string $role): string
    {
        $this->compte($role);

        return $this->postJson('/api/auth/login', ['identifiant' => $role, 'password' => 'LogiAgriERP@2026', 'device_name' => self::APPAREIL])->assertOk()->json('token');
    }

    private function api(string $jeton)
    {
        Auth::forgetGuards();
        $this->flushHeaders();

        return $this->withToken($jeton);
    }

    public function test_le_gate_unique_admet_les_ventes_et_l_elevage_et_personne_d_autre(): void
    {
        foreach (['admin' => true, 'caissier' => true, 'animalier' => true, 'comptable' => false] as $role => $attendu) {
            $this->assertSame($attendu, Gate::forUser($this->compte($role))->allows('utiliser-mode-hors-ligne'), $role);
            User::where('username', $role)->delete();
        }
    }

    public function test_l_animalier_ouvre_la_page_et_voit_l_entree_de_menu_le_comptable_est_refuse(): void
    {
        $page = $this->actingAs($this->compte('animalier'))->get('/mode-hors-ligne');
        $page->assertOk()->assertSee('Activer le mode hors ligne')->assertSee('fiches d\'élevage', false);
        $this->actingAs(User::where('username', 'animalier')->first())->get('/dashboard')->assertSee('href="/mode-hors-ligne"', false);
        \Livewire\Livewire::actingAs(User::where('username', 'animalier')->first())->test(ModeHorsLigne::class)->assertOk();

        $this->actingAs($this->compte('comptable'))->get('/mode-hors-ligne')->assertForbidden();
        $this->actingAs(User::where('username', 'comptable')->first())->get('/dashboard')->assertDontSee('href="/mode-hors-ligne"', false);
        $this->actingAs($this->compte('caissier'))->get('/mode-hors-ligne')->assertOk();
    }

    public function test_l_animalier_cree_son_jeton_et_le_serveur_dit_les_droits_de_l_ecran(): void
    {
        $jeton = $this->jeton('animalier');
        $this->assertSame(1, PersonalAccessToken::where('name', self::APPAREIL)->count());
        $droits = $this->postJson('/api/auth/login', ['identifiant' => 'animalier', 'password' => 'LogiAgriERP@2026', 'device_name' => 'pwa-autre'])->json('user.droits');
        $this->assertEqualsCanonicalizing(['view-elevage', 'manage-elevage'], $droits);
        $this->assertNotSame('', $jeton);

        $this->compte('caissier');
        $this->assertSame(['manage-ventes'], $this->postJson('/api/auth/login', ['identifiant' => 'caissier', 'password' => 'LogiAgriERP@2026', 'device_name' => 'pwa-caisse'])->json('user.droits'));
    }

    public function test_un_jeton_d_animalier_ne_peut_pas_envoyer_de_vente_mais_envoie_ses_fiches(): void
    {
        $jeton = $this->jeton('animalier');
        $cat = ProductCategory::create(['label' => 'Œufs', 'is_active' => true]);
        $produit = Product::create(['sku' => 'OEUF', 'name' => 'Œufs', 'category_id' => $cat->id, 'unit' => 'p', 'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 9000, 'tva_rate' => 0, 'stock_qty' => 100, 'is_active' => true]);
        $vente = ['id' => 'c1111111-1111-4111-8111-111111111111', 'device_id' => self::APPAREIL, 'sync_status' => 'pending', 'customer_id' => null, 'payment_mode' => 'especes', 'subtotal' => 5900, 'discount' => 0, 'total' => 5900,
            'cash_received' => 5900, 'change_due' => 0, 'status' => 'validee', 'sold_at' => now()->subMinutes(5)->toIso8601String(), 'updated_at' => now()->subMinutes(5)->toIso8601String(),
            'facture_type' => 'simple', 'lines' => [['product_id' => $produit->id, 'lot_id' => null, 'qty' => 1, 'unit_price' => 5900, 'manual_total_amount' => 5900]]];
        $r = $this->api($jeton)->postJson('/api/sync/push', ['device_id' => self::APPAREIL, 'sales' => [$vente]])->assertOk();
        $this->assertSame([], $r->json('sales.accepted'));
        $this->assertSame($vente['id'], $r->json('sales.rejected.0.id'));
        $this->assertDatabaseCount('sales', 0);

        $espece = LivestockSpecies::firstOrCreate(['code' => 'cuniculture'], ['label' => 'Cuniculture', 'is_enabled' => true]);
        $lot = LivestockLot::forceCreate(['code' => 'L1', 'species_id' => $espece->id, 'stage' => 'engraissement', 'initial_quantity' => 40, 'current_quantity' => 40, 'created_date' => '2026-01-01', 'status' => 'actif', 'is_active' => true]);
        $fiche = ['id' => 'd2222222-2222-4222-8222-222222222222', 'lot_id' => $lot->id, 'entry_date' => now()->toDateString(), 'achat' => 0, 'ne' => 0, 'mort' => 1, 'vente' => 0, 'don' => 0,
            'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 1, 'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0, 'passage_sevre_jeune' => 0,
            'cat_depart_repro' => 0, 'cat_depart_sevre' => 0, 'cat_depart_jeune' => 40, 'device_id' => self::APPAREIL, 'updated_at' => now()->toIso8601String()];
        $r = $this->api($jeton)->postJson('/api/sync/push', ['device_id' => self::APPAREIL, 'livestock_daily_entries' => [$fiche]])->assertOk();
        $this->assertSame([$fiche['id']], $r->json('livestock_daily_entries.accepted'));
        $this->assertSame(1, LivestockDailyEntry::count());
    }

    public function test_un_jeton_de_caissier_ne_peut_pas_ecrire_une_fiche_d_elevage(): void
    {
        $jeton = $this->jeton('caissier');
        $espece = LivestockSpecies::firstOrCreate(['code' => 'cuniculture'], ['label' => 'Cuniculture', 'is_enabled' => true]);
        $lot = LivestockLot::forceCreate(['code' => 'L1', 'species_id' => $espece->id, 'stage' => 'engraissement', 'initial_quantity' => 40, 'current_quantity' => 40, 'created_date' => '2026-01-01', 'status' => 'actif', 'is_active' => true]);
        $fiche = ['id' => 'd2222222-2222-4222-8222-222222222222', 'lot_id' => $lot->id, 'entry_date' => now()->toDateString(), 'achat' => 0, 'ne' => 0, 'mort' => 5, 'vente' => 0, 'don' => 0,
            'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 5, 'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0, 'passage_sevre_jeune' => 0, 'device_id' => self::APPAREIL, 'updated_at' => now()->toIso8601String()];
        $r = $this->api($jeton)->postJson('/api/sync/push', ['device_id' => self::APPAREIL, 'livestock_daily_entries' => [$fiche]])->assertOk();
        $this->assertSame([], $r->json('livestock_daily_entries.accepted'), 'un caissier n\'écrit pas la mortalité d\'une fiche');
        $this->assertSame(0, (int) LivestockDailyEntry::where('mort', '>', 0)->count());
        $this->assertSame(40, (int) LivestockLot::find($lot->id)->current_quantity);
    }

    public function test_le_tirage_reste_celui_des_droits(): void
    {
        $animalier = $this->api($this->jeton('animalier'))->getJson('/api/sync/pull?page=1')->assertOk();
        $servies = $animalier->json('tables_servies') ?? array_keys($animalier->json('data') ?? []);
        $this->assertContains('livestock_daily_entries', $servies);
        // Le tirage reste celui des droits (`PERMISSIONS_DE_TIRAGE`, rien d'élargi) : les produits et clients sont servis à tout compte, les fiches à `view-elevage` seulement.

        User::where('username', 'animalier')->delete();
        $caissier = $this->api($this->jeton('caissier'))->getJson('/api/sync/pull?page=1')->assertOk();
        $servies = $caissier->json('tables_servies') ?? array_keys($caissier->json('data') ?? []);
        // Le caissier garde le tirage des bandes et fiches dont la vente d'un sujet vivant a besoin (PWA-1b) : c'est l'ÉCRAN qui ne les montre pas (droits), pas un élargissement.
        $this->assertContains('products', $servies);
    }
}
