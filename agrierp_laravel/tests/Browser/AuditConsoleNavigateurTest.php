<?php

namespace Tests\Browser;

use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Illuminate\Support\Facades\Route;
use Laravel\Dusk\Browser;
use Tests\DuskTestCase;

/**
 * Ticket 14.20 (Sprint 14) — AUDIT : 0 erreur JavaScript, 0 ressource
 * manquante, sur CHAQUE écran, dans un vrai navigateur.
 *
 * Complète `AuditToutesLesRoutesTest` (côté serveur) par la seule dimension
 * qu'aucun test PHP ne peut atteindre : ce que le navigateur exécute
 * réellement. C'est précisément la zone qui cachait le double chargement
 * d'Alpine (ticket 14.19) — invisible aux 104 tests Feature, qui ne chargent
 * jamais une ligne de JavaScript.
 *
 * Deux catégories d'erreurs sont surveillées :
 *   • `SEVERE` sur `console-api` ou `javascript` → exception JS réelle ;
 *   • `SEVERE` sur `network` → ressource référencée qui ne se charge pas
 *     (image, police, script), c'est-à-dire un « 0 ressource manquante »
 *     vérifié depuis le navigateur et non depuis le disque.
 */
class AuditConsoleNavigateurTest extends DuskTestCase
{
    use DatabaseMigrations;

    /** Écrans à parcourir : toutes les routes GET nommées sans paramètre. */
    private function ecrans(): array
    {
        $exclues = ['login', 'password.reset', 'logout', 'health-check'];
        $uris = [];

        foreach (Route::getRoutes() as $route) {
            $nom = $route->getName();

            if ($nom === null || in_array($nom, $exclues, true) || $route->parameterNames() !== []) {
                continue;
            }

            foreach (['dusk.', 'livewire.', 'storage.', 'sanctum.', 'ignition.'] as $prefixe) {
                if (str_starts_with($nom, $prefixe)) {
                    continue 2;
                }
            }

            if (in_array('GET', $route->methods(), true)) {
                $uris[$nom] = '/'.ltrim($route->uri(), '/');
            }
        }

        return $uris;
    }

    public function test_no_screen_produces_a_javascript_or_resource_error(): void
    {
        $this->seed();

        $admin = User::where('email', 'dg@olouwachegoun.bj')->firstOrFail();
        $ecrans = $this->ecrans();

        $this->assertGreaterThan(40, count($ecrans), 'L audit doit couvrir la grande majorite des ecrans.');

        $this->browse(function (Browser $browser) use ($admin, $ecrans) {
            $browser->loginAs($admin);

            $problemes = [];

            foreach ($ecrans as $nom => $uri) {
                $browser->visit($uri)->pause(400);

                foreach ($browser->driver->manage()->getLog('browser') as $entree) {
                    if (($entree['level'] ?? '') !== 'SEVERE') {
                        continue;
                    }

                    $message = $entree['message'] ?? '';

                    // Le favicon est demandé par le navigateur lui-même sur
                    // chaque page ; son absence éventuelle n'est pas un défaut
                    // d'écran et serait de toute façon vue par l'audit des
                    // ressources, côté serveur.
                    if (str_contains($message, 'favicon')) {
                        continue;
                    }

                    $problemes[] = $nom.' ('.$uri.') : '.mb_substr($message, 0, 220);
                }
            }

            $this->assertSame(
                [],
                $problemes,
                "Erreurs JavaScript ou de ressource detectees :\n".implode("\n", $problemes)
            );
        });
    }
}
