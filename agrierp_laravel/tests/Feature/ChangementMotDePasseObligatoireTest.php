<?php

namespace Tests\Feature;

use App\Http\Middleware\ChangementMotDePasseObligatoire;
use App\Livewire\Auth\ChangementMotDePasseObligatoire as PageChangement;
use App\Models\AuditLog;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket MDP-1 — CHANGEMENT DE MOT DE PASSE FORCÉ à la première connexion (web ET API du poste).
 *
 * Tant que `users.must_change_password` est vrai : le web ne sert que la page `/changer-mot-de-passe` (middleware du
 * groupe `web`, après le verrou de session), l'API ne sert que `auth/password`, `auth/me`, `auth/logout`. Un changement
 * réussi remet le drapeau à faux, par le point de passage unique `ChangerMotDePasseAction`.
 */
class ChangementMotDePasseObligatoireTest extends TestCase
{
    use RefreshDatabase;

    private const TEMPORAIRE = 'Temp#Ferme2026';

    private User $compte;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);

        $this->compte = User::create(['name' => 'Afi', 'username' => 'afi', 'email' => 'afi@fermeolouwachegoun.com', 'password' => bcrypt(self::TEMPORAIRE), 'is_active' => true]);
        $this->compte->assignRole('admin');
        $this->compte->forceFill(['must_change_password' => true])->save();
    }

    public function test_le_middleware_est_dans_le_groupe_web_apres_le_verrou(): void
    {
        $groupes = app(\Illuminate\Foundation\Http\Kernel::class)->getMiddlewareGroups();
        $web = $groupes['web'];

        $this->assertContains(ChangementMotDePasseObligatoire::class, $web);
        $this->assertGreaterThan(
            array_search(\App\Http\Middleware\SessionVerrouillee::class, $web, true),
            array_search(ChangementMotDePasseObligatoire::class, $web, true),
            'le verrou de session passe AVANT le changement forcé',
        );
    }

    public function test_une_page_quelconque_redirige_vers_la_page_de_changement(): void
    {
        foreach (['dashboard.index', 'profil.index', 'parametres.utilisateurs'] as $nom) {
            if (! \Illuminate\Support\Facades\Route::has($nom)) {
                continue;
            }
            $this->actingAs($this->compte)->get(route($nom))->assertRedirect(route('mot-de-passe.obligatoire'));
        }
        $this->actingAs($this->compte)->get('/')->assertRedirect();
    }

    public function test_la_page_de_changement_la_deconnexion_et_la_sonde_restent_joignables(): void
    {
        $this->actingAs($this->compte)->get(route('mot-de-passe.obligatoire'))->assertOk()->assertSee('Changement de mot de passe obligatoire');
        $this->actingAs($this->compte)->get('/up')->assertOk();
        $this->actingAs($this->compte)->post(route('logout'))->assertRedirect(route('login'));
    }

    public function test_le_nom_de_composant_de_la_liste_blanche_est_celui_du_vrai_snapshot(): void
    {
        $html = $this->actingAs($this->compte)->get(route('mot-de-passe.obligatoire'))->getContent();

        $this->assertSame(1, preg_match('/wire:snapshot="([^"]+)"/', $html, $m), 'la page porte son snapshot Livewire');
        $snapshot = json_decode(html_entity_decode($m[1]), true);
        $this->assertSame(ChangementMotDePasseObligatoire::COMPOSANT, $snapshot['memo']['name']);

        // Et un envoi réel de CE composant passe le middleware (il n'est pas refusé en 403).
        $reponse = $this->actingAs($this->compte)->postJson('/livewire/update', [
            '_token' => csrf_token(),
            'components' => [['snapshot' => json_encode($snapshot), 'updates' => [], 'calls' => []]],
        ], ['X-Livewire' => 'true']);
        $this->assertNotSame(403, $reponse->getStatusCode());
    }

    public function test_un_compte_sans_drapeau_n_est_pas_gene_et_la_page_le_renvoie_a_l_accueil(): void
    {
        $this->compte->forceFill(['must_change_password' => false])->save();

        $this->actingAs($this->compte)->get(route('dashboard.index'))->assertOk();
        Livewire::actingAs($this->compte)->test(PageChangement::class)->assertRedirect(route('dashboard.index'));
    }

    public function test_un_envoi_livewire_d_un_autre_composant_est_refuse_en_403(): void
    {
        // On fabrique le snapshot d'un autre composant que la page dédiée : le serveur refuse avant tout traitement.
        $reponse = $this->actingAs($this->compte)->postJson('/livewire/update', [
            'components' => [['snapshot' => json_encode(['memo' => ['name' => 'parametres.gestion-utilisateurs']]), 'updates' => [], 'calls' => []]],
        ], ['X-Livewire' => 'true']);

        $reponse->assertStatus(403)->assertJsonPath('changement_mot_de_passe_obligatoire', true);

        // Aucun composant du tout : refusé aussi.
        $this->actingAs($this->compte)->postJson('/livewire/update', ['components' => []], ['X-Livewire' => 'true'])->assertStatus(403);
    }

    public function test_le_changement_sur_la_page_remet_le_drapeau_a_faux_et_trace_sans_secret(): void
    {
        Livewire::actingAs($this->compte)->test(PageChangement::class)
            ->set('current_password', self::TEMPORAIRE)
            ->set('new_password', 'MonSecret2026')
            ->set('new_password_confirmation', 'MonSecret2026')
            ->call('updatePassword')
            ->assertHasNoErrors()
            ->assertRedirect(route('dashboard.index'));

        $u = $this->compte->fresh();
        $this->assertFalse($u->must_change_password);
        $this->assertTrue(Hash::check('MonSecret2026', $u->password));
        $this->assertSame(1, AuditLog::where('action', 'password.updated')->where('user_id', $u->id)->count());
        $this->assertStringNotContainsString('MonSecret2026', json_encode(AuditLog::all()->toArray()));

        $this->actingAs($u)->get(route('dashboard.index'))->assertOk();
    }

    public function test_la_page_refuse_un_mauvais_temporaire_un_mot_de_passe_faible_et_le_meme_temporaire(): void
    {
        $page = fn () => Livewire::actingAs($this->compte)->test(PageChangement::class);

        $page()->set('current_password', 'pas-le-bon')->set('new_password', 'MonSecret2026')->set('new_password_confirmation', 'MonSecret2026')
            ->call('updatePassword')->assertHasErrors('current_password');
        $page()->set('current_password', self::TEMPORAIRE)->set('new_password', 'faible')->set('new_password_confirmation', 'faible')
            ->call('updatePassword')->assertHasErrors('new_password');
        $page()->set('current_password', self::TEMPORAIRE)->set('new_password', 'MonSecret2026')->set('new_password_confirmation', 'autre')
            ->call('updatePassword')->assertHasErrors('new_password');

        $meme = $page()->set('current_password', self::TEMPORAIRE)->set('new_password', self::TEMPORAIRE)->set('new_password_confirmation', self::TEMPORAIRE)
            ->call('updatePassword');
        $this->assertSame(\App\Actions\ChangerMotDePasseAction::MESSAGE_IDENTIQUE_AU_TEMPORAIRE, $meme->errors()->first('new_password'));

        $this->assertTrue($this->compte->fresh()->must_change_password, 'aucun refus ne lève le drapeau');
    }

    // ───────────────────────── API du poste ─────────────────────────

    private function seConnecter(): array
    {
        $reponse = $this->postJson('/api/auth/login', ['identifiant' => 'afi', 'password' => self::TEMPORAIRE, 'device_name' => 'poste-test'])->assertOk();

        return [$reponse->json('token'), $reponse];
    }

    public function test_la_connexion_de_l_api_annonce_le_changement_obligatoire(): void
    {
        [, $reponse] = $this->seConnecter();
        $this->assertTrue($reponse->json('must_change_password'));

        $this->compte->forceFill(['must_change_password' => false])->save();
        [, $autre] = $this->seConnecter();
        $this->assertFalse($autre->json('must_change_password'));
    }

    public function test_l_api_refuse_tout_sauf_le_changement_me_et_la_deconnexion(): void
    {
        [$jeton] = $this->seConnecter();
        $avec = ['Authorization' => 'Bearer '.$jeton];

        foreach (['/api/sync/pull', '/api/sync/coherence', '/api/sync/demande', '/api/parametres/postes'] as $chemin) {
            $this->getJson($chemin, $avec)->assertStatus(403)->assertJsonPath('must_change_password', true);
        }
        $this->postJson('/api/sync/push', ['users' => []], $avec)->assertStatus(403)->assertJsonPath('message', 'Vous devez changer votre mot de passe temporaire avant de continuer.');

        $this->getJson('/api/auth/me', $avec)->assertOk()->assertJsonPath('must_change_password', true);
    }

    public function test_le_changement_par_l_api_leve_le_drapeau_et_rend_la_synchronisation(): void
    {
        [$jeton] = $this->seConnecter();
        $avec = ['Authorization' => 'Bearer '.$jeton];

        // Le temporaire lui-même est refusé comme nouveau mot de passe.
        $this->postJson('/api/auth/password', ['current_password' => self::TEMPORAIRE, 'new_password' => self::TEMPORAIRE, 'new_password_confirmation' => self::TEMPORAIRE], $avec)
            ->assertStatus(422)->assertJsonValidationErrors('new_password');

        $this->postJson('/api/auth/password', ['current_password' => self::TEMPORAIRE, 'new_password' => 'MonSecret2026', 'new_password_confirmation' => 'MonSecret2026'], $avec)->assertOk();

        $this->assertFalse($this->compte->fresh()->must_change_password);
        $this->getJson('/api/auth/me', $avec)->assertOk()->assertJsonPath('must_change_password', false);
        $this->getJson('/api/sync/pull', $avec)->assertOk();
    }

    public function test_la_deconnexion_de_l_api_reste_possible(): void
    {
        [$jeton] = $this->seConnecter();

        $this->postJson('/api/auth/logout', [], ['Authorization' => 'Bearer '.$jeton])->assertOk();
        $this->assertSame(0, $this->compte->tokens()->count());
    }

    public function test_le_tirage_sert_le_drapeau_jamais_le_mot_de_passe(): void
    {
        $admin = User::create(['name' => 'Directeur', 'username' => 'dg', 'email' => 'dg@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $admin->assignRole('admin');

        $reponse = $this->actingAs($admin, 'sanctum')->getJson('/api/sync/pull')->assertOk();
        $ligne = collect($reponse->json('users'))->firstWhere('id', $this->compte->id);

        $this->assertTrue($ligne['must_change_password']);
        $this->assertArrayNotHasKey('password', $ligne);
        $this->assertStringNotContainsString(self::TEMPORAIRE, $reponse->getContent());
    }

    public function test_mon_profil_remet_aussi_le_drapeau_a_faux(): void
    {
        // Le point de passage est commun : Mon Profil n'est pas joignable drapeau levé, mais l'Action est la même.
        $this->compte->forceFill(['must_change_password' => false])->save();
        $this->compte->forceFill(['must_change_password' => true])->save();

        Livewire::actingAs($this->compte)->test(\App\Livewire\Profil\MonProfil::class)
            ->set('current_password', self::TEMPORAIRE)->set('new_password', 'MonSecret2026')->set('new_password_confirmation', 'MonSecret2026')
            ->call('updatePassword')->assertHasNoErrors();

        $this->assertFalse($this->compte->fresh()->must_change_password);
    }
}
