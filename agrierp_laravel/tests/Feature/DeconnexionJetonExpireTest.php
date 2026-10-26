<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Contracts\Debug\ExceptionHandler;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Session\TokenMismatchException;
use Tests\TestCase;

/**
 * « 419 Page expirée » en cliquant sur Déconnexion : la déconnexion aboutit malgré un jeton CSRF périmé.
 *
 * ⚠️ Les tests désactivent la vérification CSRF (`runningUnitTests`) : on ne peut pas provoquer le 419 par une vraie
 * requête. On fait donc rendre par le VRAI gestionnaire d'exceptions de l'application l'exception que lèverait le
 * middleware, pour la requête `POST /logout`, et pour une autre route (qui doit garder la page 419).
 */
class DeconnexionJetonExpireTest extends TestCase
{
    use RefreshDatabase;

    private function utilisateur(): User
    {
        return User::create([
            'name' => 'Test', 'username' => 'test', 'email' => 'test@fermeolouwachegoun.com',
            'password' => bcrypt('x'), 'is_active' => true,
        ]);
    }

    private function rendre(string $methode, string $chemin)
    {
        $requete = Request::create($chemin, $methode);
        $requete->setLaravelSession($this->app['session.store']);

        return $this->app->make(ExceptionHandler::class)->render($requete, new TokenMismatchException('CSRF token mismatch.'));
    }

    public function test_la_deconnexion_avec_un_jeton_perime_redirige_vers_la_connexion_sans_page_419(): void
    {
        $this->actingAs($this->utilisateur());

        $reponse = $this->rendre('POST', '/logout');

        $this->assertSame(302, $reponse->getStatusCode());
        $this->assertStringEndsWith('/login', $reponse->headers->get('Location'));
        $this->assertGuest('web');
        $this->assertSame('success', session('toast.type'));
    }

    public function test_un_autre_envoi_expire_garde_la_page_419(): void
    {
        $reponse = $this->rendre('POST', '/mon-profil');

        $this->assertSame(419, $reponse->getStatusCode());
    }

    public function test_un_get_sur_logout_ne_deconnecte_pas(): void
    {
        $this->actingAs($this->utilisateur());

        $reponse = $this->rendre('GET', '/logout');

        $this->assertSame(419, $reponse->getStatusCode());
        $this->assertAuthenticated('web');
    }
}
