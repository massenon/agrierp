<?php

namespace Tests\Feature;

use App\Livewire\Shared\EtatSynchronisationPostes;
use App\Models\AuditLog;
use App\Models\Customer;
use App\Models\Expense;
use App\Models\PosteSynchronisation;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Sale;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\ResynchronisationPostesService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket SW-1 (correction du client du 21/10/2026) — LE WEB FAIT AUSSI REVENIR LES DONNÉES VERS LES POSTES.
 *
 * Le portable sert au web parce que le poste de bureau est en panne ; réparé, le poste doit récupérer tout ce qui a été
 * saisi au web. La modale « Synchronisation » du web répond donc à : « quels postes n'ont pas encore reçu ce qui a été
 * fait au web, et puis-je forcer l'envoi ? ». Jeu calculé à la main (PRD `synchronisation-barre-superieure`, §11).
 */
class ResynchronisationPostesTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->admin = $this->compte('admin');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    private function jeton(User $u, string $poste): string
    {
        return $u->createToken($poste, ['*'], now()->addDays(90))->plainTextToken;
    }

    private function appel(string $jeton, string $methode, string $url, array $donnees = [])
    {
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', 'Bearer '.$jeton)->{$methode}($url, $donnees);
    }

    /** Écrit `updated_at` tel quel (le modèle le remettrait à maintenant). */
    private function dater(string $table, string $id, string $instant): void
    {
        DB::table($table)->where('id', $id)->update(['updated_at' => $instant]);
    }

    private function vente(string $instant): Sale
    {
        $v = Sale::create(['payment_mode' => 'especes', 'status' => 'validee', 'subtotal' => 1000, 'discount' => 0, 'total' => 1000, 'sold_at' => $instant]);
        $this->dater('sales', $v->id, $instant);

        return $v;
    }

    // ── Calcul du retard (jeu du PRD §11) ─────────────────────────────────────────────────────────────────────

    /**
     * Poste A tire le 10/10 à 12:00. Depuis : 2 ventes (11/10 et 15/10), 1 dépense (12/10), 1 article modifié (14/10),
     * 1 client créé (16/10) = 5. Avant son curseur : 1 vente (09/10) et 1 client (10/10 11:59) : non comptés.
     * Au 18/10 12:00, son dernier tirage a 8 jours : « En retard de 8 jours ».
     */
    public function test_le_retard_d_un_poste_compte_ce_qui_a_change_depuis_son_curseur(): void
    {
        $caisse = TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);
        $categorie = ProductCategory::create(['label' => 'Volailles', 'is_active' => true]);
        $this->vente('2026-10-09 09:00:00');
        $this->vente('2026-10-11 09:00:00');
        $this->vente('2026-10-15 09:00:00');
        $depense = Expense::create(['expense_date' => '2026-10-12', 'label' => 'Provende', 'category' => 'aliment', 'amount' => 1000, 'is_active' => true, 'treasury_account_id' => $caisse->id]);
        $this->dater('expenses', $depense->id, '2026-10-12 08:00:00');
        $produit = Product::create(['sku' => 'P1', 'name' => 'Poulet', 'category_id' => $categorie->id, 'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 1, 'tva_rate' => 0, 'stock_qty' => 1, 'is_active' => true]);
        $this->dater('products', $produit->id, '2026-10-14 08:00:00');
        $avant = Customer::create(['name' => 'Avant', 'phone' => '+22997000010', 'is_active' => true]);
        $this->dater('customers', $avant->id, '2026-10-10 11:59:00');
        $apres = Customer::create(['name' => 'Après', 'phone' => '+22997000011', 'is_active' => true]);
        $this->dater('customers', $apres->id, '2026-10-16 08:00:00');
        // Le produit et la caisse créés ci-dessus portent « maintenant » : on les date avant le curseur.
        $this->dater('treasury_accounts', $caisse->id, '2026-10-01 00:00:00');
        $this->dater('product_categories', $categorie->id, '2026-10-01 00:00:00');

        PosteSynchronisation::create(['poste' => 'POSTE-A', 'curseur_tirage' => '2026-10-10 12:00:00', 'dernier_tirage_le' => '2026-10-10 12:00:00']);

        $retard = app(ResynchronisationPostesService::class)->retard('POSTE-A', Carbon::parse('2026-10-18 12:00:00'));

        $this->assertSame(5, $retard['nombre']);
        $this->assertSame(['Ventes' => 2, 'Dépenses' => 1, 'Articles' => 1, 'Clients' => 1], $retard['details']);
        $this->assertSame('retard', $retard['etat']);
        $this->assertSame('En retard de 8 jours', $retard['libelle']);
        $this->assertSame('2 ventes, 1 dépense, 1 article, 1 client', $retard['resume']);
    }

    public function test_un_poste_sans_changement_est_a_jour_et_un_poste_inconnu_jamais_synchronise(): void
    {
        PosteSynchronisation::create(['poste' => 'POSTE-A', 'curseur_tirage' => '2026-10-10 12:00:00', 'dernier_tirage_le' => '2026-10-10 12:00:00']);
        $service = app(ResynchronisationPostesService::class);

        $a = $service->retard('POSTE-A', Carbon::parse('2026-10-18 12:00:00'));
        $this->assertSame([0, 'a_jour', 'À jour'], [$a['nombre'], $a['etat'], $a['libelle']]);

        $jamais = $service->retard('POSTE-NEUF', Carbon::parse('2026-10-18 12:00:00'));
        $this->assertNull($jamais['nombre'], 'inconnu : « — », jamais 0');
        $this->assertSame(['jamais', 'Jamais synchronisé'], [$jamais['etat'], $jamais['libelle']]);
    }

    public function test_le_curseur_est_compare_a_l_heure_du_serveur_et_non_a_l_heure_utc(): void
    {
        // Serveur à Porto-Novo (UTC+1) : `updated_at` est une heure murale locale.
        $fuseau = date_default_timezone_get();
        date_default_timezone_set('Africa/Porto-Novo');
        config(['app.timezone' => 'Africa/Porto-Novo']);
        try {
            $client = Customer::create(['name' => 'Dix heures', 'phone' => '+22997000012', 'is_active' => true]);
            $this->dater('customers', $client->id, '2026-10-10 11:30:00'); // 11h30 locales = 10h30 UTC

            // Le poste a tiré à 11:00 UTC = 12:00 locales : la ligne de 11:30 locales est ANTÉRIEURE, déjà reçue.
            $this->app->make(ResynchronisationPostesService::class)->noterTirage('POSTE-A', Carbon::parse('2026-10-10T11:00:00Z'));

            $retard = app(ResynchronisationPostesService::class)->retard('POSTE-A', Carbon::parse('2026-10-10 14:00:00'));
            $this->assertSame(0, $retard['nombre']);
        } finally {
            date_default_timezone_set($fuseau);
            config(['app.timezone' => 'UTC']);
        }
    }

    // ── Le serveur mémorise le curseur au tirage ──────────────────────────────────────────────────────────────

    public function test_un_tirage_complet_memorise_le_curseur_et_un_tirage_a_moitie_ne_le_fait_pas(): void
    {
        $jeton = $this->jeton($this->compte('caissier'), 'POSTE-CAISSE');
        // Deux ventes d'avant le tirage : avec `taille=1`, la seconde descend à la page suivante.
        Carbon::setTestNow('2026-10-20 09:00:00');
        Sale::create(['payment_mode' => 'especes', 'status' => 'validee', 'subtotal' => 1000, 'discount' => 0, 'total' => 1000, 'sold_at' => '2026-10-20 08:00:00']);
        Sale::create(['payment_mode' => 'especes', 'status' => 'validee', 'subtotal' => 2000, 'discount' => 0, 'total' => 2000, 'sold_at' => '2026-10-20 08:30:00']);
        Carbon::setTestNow('2026-10-20 10:00:00');

        $reponse = $this->appel($jeton, 'getJson', '/api/sync/pull?page=1&taille=1')->assertOk()->json();
        $this->assertNotNull($reponse['page_suivante'] ?? null, 'le tirage est à moitié fait');
        $this->assertSame(0, PosteSynchronisation::where('poste', 'POSTE-CAISSE')->count(), 'curseur non avancé : le poste non plus ne l\'avance qu\'à la dernière page');

        $this->appel($jeton, 'getJson', '/api/sync/pull')->assertOk();
        $ligne = PosteSynchronisation::where('poste', 'POSTE-CAISSE')->sole();
        $this->assertSame('2026-10-20 09:59:55', $ligne->curseur_tirage->format('Y-m-d H:i:s'), 'début du tirage reculé de l\'horizon (5 s)');
        $this->assertSame('2026-10-20 10:00:00', $ligne->dernier_tirage_le->format('Y-m-d H:i:s'));
    }

    // ── Drapeau de resynchronisation : posé, lu, honoré, acquitté ─────────────────────────────────────────────

    public function test_le_drapeau_est_pose_lu_au_ping_et_au_tirage_puis_acquitte(): void
    {
        $caissier = $this->compte('caissier');
        $jeton = $this->jeton($caissier, 'POSTE-CAISSE');
        $autre = $this->jeton($this->compte('animalier'), 'POSTE-ELEVAGE');

        $this->assertArrayNotHasKey('resynchronisation', $this->appel($jeton, 'getJson', '/api/sync/demande')->json(), 'sans drapeau : clé absente');

        Carbon::setTestNow('2026-10-20 10:00:00');
        app(ResynchronisationPostesService::class)->demanderPoste('POSTE-CAISSE', $this->admin);

        // Le ping (30 s) le lit, et le relit tant qu'il n'est pas acquitté (contrairement à la demande de synchro).
        Carbon::setTestNow('2026-10-20 10:00:20');
        $ping = $this->appel($jeton, 'getJson', '/api/sync/demande')->assertOk()->json();
        $this->assertTrue($ping['resynchronisation']);
        $this->assertTrue($this->appel($jeton, 'getJson', '/api/sync/demande')->json('resynchronisation'), 'tant que non acquitté');
        $this->assertArrayNotHasKey('resynchronisation', $this->appel($autre, 'getJson', '/api/sync/demande')->json(), 'l\'autre poste n\'est pas visé');

        // Le tirage le porte aussi (page 1 paginée et réponse non paginée).
        $demandeeLe = $this->appel($jeton, 'getJson', '/api/sync/pull?page=1')->assertOk()->json('resynchronisation_demandee_le');
        $this->assertTrue(Carbon::parse($demandeeLe)->equalTo(Carbon::parse('2026-10-20 10:00:00')), 'l\'instant de la demande, tel que posé');
        $this->assertSame($demandeeLe, $this->appel($jeton, 'getJson', '/api/sync/pull')->json('resynchronisation_demandee_le'));
        $this->assertNull($this->appel($autre, 'getJson', '/api/sync/pull')->json('resynchronisation_demandee_le'));

        // Un acquittement d'AVANT la demande ne la fait pas tomber (une nouvelle demande est arrivée pendant le tirage).
        $this->appel($jeton, 'postJson', '/api/sync/resynchronisation/acquittement', ['demandee_le' => Carbon::parse('2026-10-20 09:00:00')->toIso8601String()])
            ->assertOk()->assertJsonPath('acquittee', false);
        $this->assertTrue($this->appel($jeton, 'getJson', '/api/sync/demande')->json('resynchronisation'));

        // Le bon acquittement fait tomber le drapeau.
        $this->appel($jeton, 'postJson', '/api/sync/resynchronisation/acquittement', ['demandee_le' => $demandeeLe])
            ->assertOk()->assertJsonPath('acquittee', true);
        $this->assertArrayNotHasKey('resynchronisation', $this->appel($jeton, 'getJson', '/api/sync/demande')->json(), 'sans drapeau : clé absente');
        $this->assertNull($this->appel($jeton, 'getJson', '/api/sync/pull')->json('resynchronisation_demandee_le'));
        $ligne = PosteSynchronisation::where('poste', 'POSTE-CAISSE')->sole();
        $this->assertNull($ligne->resync_demandee_le);
        $this->assertNotNull($ligne->resync_acquittee_le);
    }

    public function test_l_acquittement_exige_un_jeton_et_une_date(): void
    {
        $this->postJson('/api/sync/resynchronisation/acquittement', ['demandee_le' => '2026-10-20T10:00:00+00:00'])->assertUnauthorized();
        $this->appel($this->jeton($this->compte('caissier'), 'POSTE-CAISSE'), 'postJson', '/api/sync/resynchronisation/acquittement', [])
            ->assertUnprocessable();
    }

    // ── Modale web : « Renvoyer vers ce poste », « Renvoyer vers tous les postes » ────────────────────────────

    public function test_la_modale_montre_le_retard_de_chaque_poste_et_renvoie_vers_un_poste_ou_tous(): void
    {
        Carbon::setTestNow('2026-10-18 12:00:00');
        $this->jeton($this->compte('caissier'), 'POSTE-A');
        $this->jeton($this->compte('animalier'), 'POSTE-B');
        $this->jeton($this->compte('comptable'), 'POSTE-NEUF');
        $client = Customer::create(['name' => 'Tard', 'phone' => '+22997000013', 'is_active' => true]);
        $this->dater('customers', $client->id, '2026-10-16 08:00:00');
        PosteSynchronisation::create(['poste' => 'POSTE-A', 'curseur_tirage' => '2026-10-10 12:00:00', 'dernier_tirage_le' => '2026-10-10 12:00:00']);
        PosteSynchronisation::create(['poste' => 'POSTE-B', 'curseur_tirage' => '2026-10-18 11:00:00', 'dernier_tirage_le' => '2026-10-18 11:00:00']);

        $this->actingAs($this->admin);
        Livewire::test(EtatSynchronisationPostes::class)
            ->assertSee('Modifications du site depuis son dernier tirage')
            ->assertSee('1 client')
            ->assertSee('En retard de 8 jours')
            ->assertSee('À jour')
            ->assertSee('Jamais synchronisé')
            ->assertSee('Renvoyer vers ce poste')
            ->assertSee('Renvoyer vers tous les postes')
            ->call('renvoyer', 'POSTE-A')
            ->assertDispatched('toast', type: 'success')
            ->assertSee('Resynchronisation demandée')
            ->call('renvoyer', 'POSTE-INCONNU')
            ->assertDispatched('toast', message: 'Poste inconnu du serveur : renvoi non demandé.', type: 'error');

        $this->assertNotNull(PosteSynchronisation::where('poste', 'POSTE-A')->sole()->resync_demandee_le);
        $this->assertNull(PosteSynchronisation::where('poste', 'POSTE-B')->sole()->resync_demandee_le);

        Livewire::test(EtatSynchronisationPostes::class)->call('renvoyerATous')->assertDispatched('toast', type: 'success');
        foreach (['POSTE-A', 'POSTE-B', 'POSTE-NEUF'] as $poste) {
            $this->assertNotNull(PosteSynchronisation::where('poste', $poste)->sole()->resync_demandee_le, $poste);
        }
    }

    public function test_le_renvoi_est_reserve_a_l_administrateur_et_journalise_dans_l_audit(): void
    {
        $this->jeton($this->compte('caissier'), 'POSTE-A');

        $this->actingAs($this->compte('comptable'));
        Livewire::test(EtatSynchronisationPostes::class)->assertForbidden();

        $this->actingAs($this->admin);
        Livewire::test(EtatSynchronisationPostes::class)->call('renvoyer', 'POSTE-A')->call('renvoyerATous');

        $poste = AuditLog::where('action', 'sync.renvoi_poste:POSTE-A')->sole();
        $this->assertSame($this->admin->id, $poste->user_id, 'qui');
        $this->assertNotNull($poste->created_at, 'quand');
        $this->assertSame(1, AuditLog::where('action', 'sync.renvoi_tous')->count());
        // Le service lui-même ne s'ouvre à personne d'autre : pas d'appel sans administrateur.
        $this->assertSame(0, AuditLog::where('action', 'like', 'sync.renvoi_poste:%')->where('user_id', '<>', $this->admin->id)->count());
    }

    public function test_un_renvoi_vers_un_poste_expire_ou_inconnu_ne_laisse_aucun_drapeau(): void
    {
        $this->actingAs($this->admin);
        Livewire::test(EtatSynchronisationPostes::class)->call('renvoyer', 'POSTE-FANTOME');

        $this->assertSame(0, PosteSynchronisation::whereNotNull('resync_demandee_le')->count());
        $this->assertSame(0, AuditLog::where('action', 'like', 'sync.renvoi%')->count());
    }
}
