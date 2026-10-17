<?php

namespace Tests\Browser;

use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Laravel\Dusk\Browser;
use Tests\DuskTestCase;

/**
 * Ticket 13.1 — Parcours critique 6/8 (Document 07 §4) : Navigation
 * complète sidebar. "Chaque lien du sidebar testé pour chacun des 4
 * rôles RBAC, vérifiant à la fois la visibilité du lien ET l'accès réel
 * à la route (un lien masqué ne suffit pas — vérifier qu'une requête
 * directe sur l'URL est aussi bloquée pour un rôle non autorisé)."
 *
 * 🔴→✅ C'EST CE PARCOURS, EN COURS D'ÉCRITURE, QUI A RÉVÉLÉ LE GAP RBAC
 * LE PLUS SÉRIEUX DE TOUT LE PROJET : sur 42 routes métier, une seule
 * vérifiait réellement une permission Spatie — les 41 autres n'étaient
 * protégées que par `auth` (n'importe quel utilisateur connecté, quel
 * que soit son rôle, atteignait n'importe quel écran par URL directe).
 * Les permissions existaient et étaient déjà correctement assignées aux
 * 4 rôles (`RolesAndPermissionsSeeder`) — elles n'étaient simplement
 * jamais vérifiées côté route. CORRIGÉ DANS CE MÊME TICKET (voir le
 * docblock en tête de `routes/web.php`) plutôt que seulement constaté :
 * chaque route métier porte désormais `can:{permission}` mappée à son
 * module réel. Ce test vérifie directement ce correctif.
 *
 * ⚠️ GAP DISTINCT ET DÉLIBÉRÉMENT NON CORRIGÉ DANS CE TICKET : la
 * protection ci-dessus couvre la ROUTE (chargement initial de l'écran).
 * Document 06 exige la vérification "sur chaque route ET chaque action
 * Livewire" — un contrôle `$this->authorize()`/`Gate::` à l'intérieur des
 * méthodes d'action (ex. `saveAccount()`, `archiveEntry()`) reste une
 * seconde couche de défense en profondeur, quasi absente aujourd'hui
 * (1 seul composant sur 76 en dispose). Risque pratique atténué par le
 * fait qu'une requête Livewire de mise à jour nécessite un snapshot
 * signé obtenu via le rendu initial déjà protégé par la route — mais pas
 * nul (session compromise, permission révoquée en cours de session).
 * Retrofitter `authorize()` sur les actions sensibles des 76 composants
 * est un chantier à part entière, hors périmètre raisonnable de ce
 * ticket — signalé explicitement plutôt que bâclé en vitesse.
 */
class SidebarRbacNavigationTest extends DuskTestCase
{
    use DatabaseMigrations;

    /**
     * @return array<string, array{email: string, allowed: string[], forbidden: string[]}>
     */
    private function roleMatrix(): array
    {
        return [
            'animalier' => [
                'email' => 'elevage@olouwachegoun.bj',
                'allowed' => ['/gestion-elevage', '/gestion-bandes'],
                'forbidden' => ['/plan-comptable', '/cloture-exercice', '/administration', '/personnel-stages'],
            ],
            'caissier' => [
                'email' => 'caisse@olouwachegoun.bj',
                'allowed' => ['/ventes-devis', '/creances-clients'],
                'forbidden' => ['/gestion-elevage', '/plan-comptable', '/cloture-exercice', '/administration'],
            ],
            'comptable' => [
                'email' => 'compta@olouwachegoun.bj',
                'allowed' => ['/plan-comptable', '/journal-comptable', '/cloture-exercice', '/rapports-exports'],
                'forbidden' => ['/gestion-elevage', '/ventes-devis', '/administration', '/personnel-stages'],
            ],
        ];
    }

    public function test_each_non_admin_role_is_blocked_from_direct_url_access_outside_its_scope(): void
    {
        $this->seed();

        foreach ($this->roleMatrix() as $role => $matrix) {
            $user = User::where('email', $matrix['email'])->firstOrFail();

            $this->browse(function (Browser $browser) use ($user, $matrix, $role) {
                foreach ($matrix['allowed'] as $path) {
                    $browser->loginAs($user)
                        ->visit($path)
                        ->assertPathIs($path, "Rôle {$role} devrait accéder à {$path}.");
                }

                foreach ($matrix['forbidden'] as $path) {
                    // 🔴→✅ TICKET 14.22 — ATTENTE CORRIGEE. Ce parcours exigeait
                    // `assertPathIsNot($path)`, c'est-a-dire une REDIRECTION hors
                    // de l'URL interdite. Or le middleware `can:` de Laravel
                    // renvoie un 403 EN RESTANT sur l'URL : le chemin ne change
                    // pas, et l'assertion ne pouvait donc jamais passer.
                    //
                    // Le blocage lui-meme est correct et desormais prouve cote
                    // serveur sur les 4 roles x toutes les routes
                    // (`AuditRbacRoutesTest`, ticket 14.22). C'etait bien
                    // l'attente du test qui etait fausse, ecrite sans jamais
                    // avoir ete executee.
                    $browser->loginAs($user)
                        ->visit($path)
                        ->pause(300)
                        // Le corps visible d'un 403 Laravel affiche « 403 This action
                        // is unauthorized. » — « Forbidden » n'est que dans le <title>,
                        // que `assertSee` (texte du body) ne lit pas. On assertionne
                        // sur le code, stable quelle que soit la langue.
                        ->assertSee('403');
                }
            });
        }
    }

    public function test_admin_reaches_every_hub_route(): void
    {
        $this->seed();
        $admin = User::where('email', 'dg@olouwachegoun.bj')->firstOrFail();

        $hubs = [
            '/gestion-elevage', '/ventes-devis', '/achats-commandes', '/gestion-stocks',
            '/facturation', '/personnel-stages', '/administration', '/comptabilite-hub',
            '/parametres-hub', '/rapports-exports',
        ];

        $this->browse(function (Browser $browser) use ($admin, $hubs) {
            foreach ($hubs as $path) {
                $browser->loginAs($admin)->visit($path)->assertPathIs($path);
            }
        });
    }
}
