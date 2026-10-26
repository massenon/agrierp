<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\RateLimiter;

/**
 * Sprint VW (VW1) — déverrouiller = prouver le mot de passe du compte, côté serveur, avec le limiteur de la
 * connexion (5 essais / 15 minutes) et, à 10 échecs cumulés dans la session, la déconnexion complète.
 */
class VerrouSessionDeverrouillageTest extends VerrouSessionBase
{
    public function test_le_bon_mot_de_passe_deverrouille(): void
    {
        $this->verrouille();

        $this->postJson('/deverrouiller', ['password' => self::MOT_DE_PASSE])
            ->assertOk()
            ->assertJsonPath('verrouille', false);

        $this->assertNull(session('session_locked'));
        $this->get('/mon-profil')->assertOk();
    }

    public function test_un_mauvais_mot_de_passe_reste_verrouille_avec_le_message_du_domaine(): void
    {
        $this->verrouille();

        $this->postJson('/deverrouiller', ['password' => 'MauvaisMotDePasse1'])
            ->assertStatus(422)
            ->assertJsonPath('message', 'Mot de passe incorrect.');

        $this->assertTrue(session('session_locked') === true);
        $this->get('/mon-profil')->assertRedirect(route('session.verrou'));
    }

    public function test_un_mot_de_passe_vide_est_refuse(): void
    {
        $this->verrouille();

        $this->postJson('/deverrouiller', ['password' => ''])
            ->assertStatus(422)
            ->assertJsonPath('message', 'Le mot de passe est obligatoire.');
        $this->assertTrue(session('session_locked') === true);
    }

    public function test_deverrouiller_une_session_non_verrouillee_est_sans_effet(): void
    {
        $this->actingAs($this->utilisateur());

        $this->postJson('/deverrouiller', ['password' => 'peu importe'])->assertOk();
    }

    public function test_le_retour_est_la_page_demandee_avant_le_verrou(): void
    {
        $this->verrouille();
        $this->get('/mon-profil');

        $this->postJson('/deverrouiller', ['password' => self::MOT_DE_PASSE])
            ->assertOk()
            ->assertJsonPath('retour', url('/mon-profil'));
    }

    public function test_le_5e_echec_declenche_le_limiteur_de_la_connexion(): void
    {
        $this->verrouille();

        foreach (range(1, 4) as $i) {
            $this->postJson('/deverrouiller', ['password' => 'Faux'.$i])->assertStatus(422);
        }
        $cinquieme = $this->postJson('/deverrouiller', ['password' => 'Faux5']);
        $cinquieme->assertStatus(429)->assertJsonPath('secondes', fn ($s) => $s > 890 && $s <= 900);
        $this->assertStringStartsWith("Trop d'essais. Réessayez dans ", $cinquieme->json('message'));

        // Bloqué : même le BON mot de passe est refusé, et la session reste verrouillée.
        $this->postJson('/deverrouiller', ['password' => self::MOT_DE_PASSE])->assertStatus(429);
        $this->assertTrue(session('session_locked') === true);
    }

    public function test_le_limiteur_est_celui_de_la_connexion(): void
    {
        $this->assertSame(\App\Livewire\Auth\Login::MAX_TENTATIVES, \App\Services\VerrouSessionService::MAX_TENTATIVES);
        $this->assertSame(5, \App\Livewire\Auth\Login::MAX_TENTATIVES);
        $this->assertSame(900, \App\Livewire\Auth\Login::DUREE_BLOCAGE);
    }

    public function test_un_succes_remet_le_limiteur_et_le_compteur_a_zero(): void
    {
        $u = $this->verrouille();

        foreach (range(1, 3) as $i) {
            $this->postJson('/deverrouiller', ['password' => 'Faux'.$i])->assertStatus(422);
        }
        $this->postJson('/deverrouiller', ['password' => self::MOT_DE_PASSE])->assertOk();
        $this->assertSame(0, RateLimiter::attempts($this->cleLimiteur($u)));
        $this->assertNull(session('session_lock_failures'));

        // Reverrouillé : quatre échecs de plus ne bloquent pas (3 + 4 = 7 cumulés SANS la remise à zéro).
        $this->postJson('/verrouiller')->assertOk();
        foreach (range(1, 4) as $i) {
            $this->postJson('/deverrouiller', ['password' => 'Faux'.$i])->assertStatus(422);
        }
    }

    public function test_dix_echecs_cumules_deconnectent_completement(): void
    {
        $u = $this->verrouille();

        // 9 premiers échecs : on passe sous le limiteur en le vidant entre deux séries de 4.
        foreach (range(1, 9) as $i) {
            $this->postJson('/deverrouiller', ['password' => 'Faux'.$i]);
            if ($i % 4 === 0) {
                RateLimiter::clear($this->cleLimiteur($u));
            }
        }
        RateLimiter::clear($this->cleLimiteur($u));
        $this->assertAuthenticatedAs($u);

        $dixieme = $this->postJson('/deverrouiller', ['password' => 'Faux10']);

        $dixieme->assertStatus(401)
            ->assertJsonPath('deconnecte', true)
            ->assertJsonPath('redirect', route('login'));
        $this->assertStringStartsWith("Trop d'échecs :", $dixieme->json('message'));
        $this->assertGuest();
        $this->assertNull(session('session_locked'));
    }

    public function test_neuf_echecs_ne_deconnectent_pas(): void
    {
        $u = $this->verrouille();

        foreach (range(1, 9) as $i) {
            $this->postJson('/deverrouiller', ['password' => 'Faux'.$i]);
            if ($i % 4 === 0) {
                RateLimiter::clear($this->cleLimiteur($u));
            }
        }

        $this->assertAuthenticatedAs($u);
        $this->assertTrue(session('session_locked') === true);
    }

    public function test_le_formulaire_sans_javascript_redirige(): void
    {
        $this->verrouille();

        $this->post('/deverrouiller', ['password' => 'Faux'])
            ->assertRedirect(route('session.verrou'))
            ->assertSessionHasErrors(['password' => 'Mot de passe incorrect.']);

        $this->post('/deverrouiller', ['password' => self::MOT_DE_PASSE])
            ->assertRedirect(route('dashboard.index'));
        $this->assertNull(session('session_locked'));
    }

    public function test_le_cookie_de_rappel_est_retire_au_verrouillage_et_rendu_au_deverrouillage(): void
    {
        $u = $this->utilisateur();
        $this->actingAs($u);
        $rappel = Auth::guard('web')->getRecallerName();

        $this->withCredentials()->withCookie($rappel, $u->id.'|jeton|hash')
            ->postJson('/verrouiller')
            ->assertOk()
            ->assertCookieExpired($rappel);

        $this->postJson('/deverrouiller', ['password' => self::MOT_DE_PASSE])
            ->assertOk()
            ->assertCookieNotExpired($rappel);
    }

    public function test_sans_cookie_de_rappel_aucun_n_est_cree(): void
    {
        $this->actingAs($this->utilisateur());
        $rappel = Auth::guard('web')->getRecallerName();

        $this->postJson('/verrouiller')->assertOk()->assertCookieMissing($rappel);
        $this->postJson('/deverrouiller', ['password' => self::MOT_DE_PASSE])->assertOk()->assertCookieMissing($rappel);
    }
}
