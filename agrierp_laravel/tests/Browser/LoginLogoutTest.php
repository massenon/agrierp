<?php

namespace Tests\Browser;

use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Laravel\Dusk\Browser;
use Tests\DuskTestCase;

/**
 * Ticket 13.1 — Parcours critique 1/8 (Document 07 §4) : Connexion →
 * Déconnexion. Saisie identifiants, redirection dashboard, toast de
 * bienvenue, déconnexion, invalidation de session vérifiée (retour
 * arrière navigateur ne doit pas réafficher de contenu protégé).
 */
/**
 * Ticket 14.19 — selecteurs rendus fiables.
 *
 * Ces parcours ont ete ecrits sans jamais etre executes : ils ciblaient le
 * bouton par son LIBELLE (`press('Se connecter')`). Or Selenium lit le texte
 * REELLEMENT RENDU, ou les ligatures des icones Material Symbols
 * ("lock_open", "progress_activity") s'ajoutent au libelle, lui-meme passe en
 * majuscules par la classe `uppercase`. Aucun selecteur par libelle ne
 * pouvait donc correspondre.
 *
 * Bascule sur l'attribut `dusk`, la methode recommandee par Dusk :
 * insensible au style, aux icones et aux traductions.
 */
class LoginLogoutTest extends DuskTestCase
{
    use DatabaseMigrations;

    /**
     * ⚠️ LE LIMITEUR DE TENTATIVES VIT DANS LE CACHE, PAS EN BASE.
     * `DatabaseMigrations` remet la base a zero mais laisse intacts les
     * compteurs de `RateLimiter` : 5 echecs de connexion depuis la meme IP
     * verrouillent le compte 15 minutes, et le test suivant ne verrait plus
     * « Identifiants incorrects » mais la banniere de verrouillage — un test
     * qui passe seul et echoue en serie. Purge explicite avant chaque cas.
     */
    protected function setUp(): void
    {
        parent::setUp();

        \Illuminate\Support\Facades\Cache::clear();
    }

    public function test_login_redirects_to_dashboard_with_welcome_toast(): void
    {
        $this->seed();

        $this->browse(function (Browser $browser) {
            $browser->visit('/login')
                ->type('identifiant', 'admin')
                ->type('password', 'AgriERP@2026')
                ->press('@login-submit')
                ->waitForLocation('/dashboard', 10)
                ->assertPathIs('/dashboard')
                ->waitForText('Connexion réussie', 5)
                ->assertSee('Connexion réussie');
        });
    }

    public function test_logout_invalidates_session_and_blocks_back_navigation(): void
    {
        $this->seed();
        $user = User::where('email', 'dg@fermeolouwachegoun.com')->firstOrFail();

        $this->browse(function (Browser $browser) use ($user) {
            $browser->loginAs($user)
                ->visit('/dashboard')
                ->assertPathIs('/dashboard')
                ->click('#admin-profile-btn')
                ->waitFor('#dd-profile', 3)
                // ⚠️ `clickLink()` echouait ici avec « Cannot read properties of
                // undefined (reading 'click') » : « Déconnexion » n'est PAS un lien
                // mais le bouton d'un formulaire POST. Selecteur `dusk` pose sur ce
                // bouton (ticket 14.28) — insensible aussi a la ligature de l'icone,
                // qui rend son texte « logoutDéconnexion ».
                ->press('@logout')
                ->waitForLocation('/login', 10)
                ->assertPathIs('/login')
                // Tentative de retour arrière après déconnexion — ne doit
                // jamais réafficher le dashboard protégé.
                ->script('window.history.back()');

            $browser->pause(500)
                ->assertPathIsNot('/dashboard');
        });
    }

    public function test_invalid_credentials_show_error_without_redirect(): void
    {
        $this->seed();

        $this->browse(function (Browser $browser) {
            $browser->visit('/login')
                ->type('identifiant', 'admin')
                ->type('password', 'mauvais-mot-de-passe')
                ->press('@login-submit')
                // ⚠️ `pause(500)` ne suffisait pas : l'erreur arrive par un
                // aller-retour Livewire, pas par un rechargement de page. La capture
                // d'echec montrait le formulaire soumis SANS message — un delai fixe
                // trop court, jamais un defaut de l'application (le message existe
                // bien : `Login::submit()` ajoute « Identifiants incorrects. »).
                ->waitForText('Identifiants incorrects', 10)
                ->assertPathIs('/login')
                ->assertSee('Identifiants incorrects');
        });
    }
}
