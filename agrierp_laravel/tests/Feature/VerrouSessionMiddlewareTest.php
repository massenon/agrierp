<?php

namespace Tests\Feature;

use App\Http\Middleware\SessionVerrouillee;
use Illuminate\Routing\Router;
use Laravel\Sanctum\Sanctum;

/**
 * Sprint VW (VW1) — le verrou est EFFECTIF CÔTÉ SERVEUR : un navigateur manipulé (surcouche retirée, requête
 * rejouée à la main) n'obtient rien tant que la session est verrouillée.
 */
class VerrouSessionMiddlewareTest extends VerrouSessionBase
{
    public function test_session_deverrouillee_les_pages_repondent(): void
    {
        $this->actingAs($this->utilisateur());

        $this->get('/mon-profil')->assertOk();
        $this->get('/dashboard')->assertOk();
    }

    public function test_session_verrouillee_une_page_redirige_vers_l_ecran_de_verrouillage(): void
    {
        $this->verrouille();

        $this->get('/mon-profil')->assertRedirect(route('session.verrou'));
        $this->get('/dashboard')->assertRedirect(route('session.verrou'));
        $this->get('/gestion-elevage')->assertRedirect(route('session.verrou'));
    }

    public function test_la_page_demandee_est_memorisee_pour_le_retour(): void
    {
        $this->verrouille();

        $this->get('/mon-profil')->assertSessionHas('url.apres_deverrouillage', url('/mon-profil'));
    }

    public function test_session_verrouillee_une_requete_json_recoit_423(): void
    {
        $this->verrouille();

        $this->getJson('/mon-profil')
            ->assertStatus(423)
            ->assertJsonPath('verrouille', true)
            ->assertJsonPath('url', route('session.verrou'));
    }

    public function test_session_verrouillee_un_envoi_livewire_est_refuse_en_423(): void
    {
        $this->verrouille();

        $this->postJson('/livewire/update', ['components' => []], ['X-Livewire' => ''])
            ->assertStatus(423)
            ->assertJsonPath('verrouille', true);
    }

    public function test_session_deverrouillee_un_envoi_livewire_n_est_pas_refuse_par_le_verrou(): void
    {
        $this->actingAs($this->utilisateur());

        $this->assertNotSame(423, $this->postJson('/livewire/update', ['components' => []], ['X-Livewire' => ''])->getStatusCode());
    }

    public function test_session_verrouillee_un_envoi_de_fichier_ou_un_formulaire_est_redirige(): void
    {
        $this->verrouille();

        $this->post('/livewire/upload-file')->assertRedirect(route('session.verrou'));
        $this->postJson('/livewire/upload-file')->assertStatus(423);
    }

    public function test_les_routes_exemptees_restent_joignables_verrouille(): void
    {
        $this->verrouille();

        $this->get(route('session.verrou'))->assertOk();
        $this->get('/welcome')->assertOk();
        $this->get('/presentation')->assertOk();
        $this->get('/up')->assertOk();
        $this->get('/livewire/livewire.js')->assertOk();
    }

    public function test_la_deconnexion_reste_possible_verrouille(): void
    {
        $this->verrouille();

        $this->post('/logout')->assertRedirect(route('login'));
        $this->assertGuest();
    }

    public function test_verrouiller_pose_l_etat_et_il_survit_au_rechargement(): void
    {
        $this->actingAs($this->utilisateur());

        $this->postJson('/verrouiller')->assertOk()->assertJsonPath('verrouille', true);
        $this->assertTrue(session('session_locked') === true);

        // « Rechargement » et « autre onglet » : de nouvelles requêtes de la même session.
        $this->get('/mon-profil')->assertRedirect(route('session.verrou'));
        $this->get('/dashboard')->assertRedirect(route('session.verrou'));
    }

    public function test_verrouiller_deux_fois_est_sans_effet(): void
    {
        $this->actingAs($this->utilisateur());

        $this->postJson('/verrouiller')->assertOk();
        $this->postJson('/verrouiller')->assertOk()->assertJsonPath('verrouille', true);
    }

    public function test_un_invite_n_est_pas_concerne_meme_avec_un_drapeau_perime(): void
    {
        $this->withSession(['session_locked' => true]);

        $this->get('/login')->assertOk();
        $this->postJson('/verrouiller')->assertUnauthorized();
    }

    public function test_verrouiller_exige_d_etre_connecte(): void
    {
        $this->postJson('/verrouiller')->assertUnauthorized();
        $this->postJson('/deverrouiller', ['password' => 'x'])->assertUnauthorized();
    }

    public function test_l_api_du_poste_n_a_pas_de_session_donc_pas_de_verrou(): void
    {
        $u = $this->utilisateur();
        Sanctum::actingAs($u);
        $this->withSession(['session_locked' => true]);

        $this->getJson('/api/auth/me')->assertOk();
    }

    public function test_le_middleware_est_dans_le_groupe_web(): void
    {
        // Garde-fou : sans lui dans le groupe, Livewire (`/livewire/update`) et toutes les pages échappent au verrou.
        $groupes = app(Router::class)->getMiddlewareGroups();

        $this->assertContains(SessionVerrouillee::class, $groupes['web']);
        $this->assertNotContains(SessionVerrouillee::class, $groupes['api'] ?? []);
    }
}
