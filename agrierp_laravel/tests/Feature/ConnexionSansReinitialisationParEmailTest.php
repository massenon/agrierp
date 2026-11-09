<?php

namespace Tests\Feature;

use App\Livewire\Auth\Login;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Route;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket MDP-1 — décision du client : plus de « Mot de passe oublié ? » par e-mail. Le lien est remplacé par le texte
 * NON cliquable « Contactez l'administrateur » (même emplacement, mêmes mots au poste : `login_screen.dart`).
 */
class ConnexionSansReinitialisationParEmailTest extends TestCase
{
    use RefreshDatabase;

    public function test_l_ecran_de_connexion_dit_contactez_l_administrateur_sans_lien_ni_fenetre(): void
    {
        $html = $this->get('/login')->assertOk()->getContent();

        $this->assertStringContainsString("Contactez l'administrateur", $html);
        $this->assertStringNotContainsString('Mot de passe oublié', $html);
        $this->assertStringNotContainsString('forgot-password', $html);
        $this->assertStringNotContainsString('Envoyer le lien', $html);

        // Texte NON cliquable : ni bouton ni lien autour.
        $this->assertSame(1, preg_match('#<(\w+)[^>]*>\s*Contactez l\'administrateur\s*</\1>#', $html, $m));
        $this->assertSame('span', $m[1]);
    }

    public function test_la_reinitialisation_par_email_n_existe_plus(): void
    {
        $this->assertFalse(method_exists(Login::class, 'sendResetLink'));
        $this->assertFalse(property_exists(Login::class, 'forgotEmail'));
        $this->assertFileDoesNotExist(app_path('Livewire/Auth/ResetPassword.php'));
        $this->assertFalse(Route::has('password.reset'));
        $this->get('/reset-password/un-jeton')->assertNotFound();
        $this->assertFileDoesNotExist(resource_path('views/livewire/auth/reset-password.blade.php'));
    }

    public function test_la_connexion_ordinaire_fonctionne_toujours(): void
    {
        Livewire::test(Login::class)->set('identifiant', '')->call('submit')->assertHasErrors('identifiant');
    }
}
