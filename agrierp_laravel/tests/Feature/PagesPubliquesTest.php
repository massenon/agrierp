<?php

namespace Tests\Feature;

use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.15 (Sprint 14) — pages publiques (accueil et présentation).
 *
 * Pages statiques : le seul enjeu réel est le ROUTAGE — qu'elles restent
 * accessibles sans authentification, qu'elles le restent aussi une fois
 * connecté (ce sont des pages de présentation, pas des écrans applicatifs),
 * et que la racine du site oriente correctement selon l'état de connexion.
 */
class PagesPubliquesTest extends TestCase
{
    use RefreshDatabase;

    /**
     * 🔴 GAP D'ENVIRONNEMENT TROUVÉ EN ÉCRIVANT CE TEST : `@vite` exige
     * `public/build/manifest.json`, produit par `npm run build` — or
     * `node_modules/` et `public/build/` n'existent pas dans cette
     * installation. Toute page rendue via un layout lève donc une
     * `ViteManifestNotFoundException` : **l'application ne peut afficher
     * aucun écran dans un navigateur en l'état.**
     *
     * Le défaut était resté invisible parce que TOUS les tests précédents
     * passent par `Livewire::test()`, qui rend la vue du composant sans son
     * layout. Ce test est le premier à faire une vraie requête HTTP de page.
     *
     * `withoutVite()` neutralise la compilation d'assets pour ces tests, dont
     * l'objet est le routage et le contenu — pas le bundling. Cela ne corrige
     * pas l'installation : `npm install && npm run build` reste requis avant
     * toute mise en service (voir `README_SPRINT0.md`, ticket 14.15).
     */
    protected function setUp(): void
    {
        parent::setUp();

        $this->withoutVite();
    }

    private function utilisateur(): User
    {
        Permission::findOrCreate('view-comptabilite', 'web');
        $role = Role::findOrCreate('admin', 'web');

        $user = User::create([
            'name' => 'Test',
            'email' => 'test@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'),
        ]);
        $user->assignRole($role);

        return $user;
    }

    public function test_public_pages_are_reachable_without_logging_in(): void
    {
        $this->get('/welcome')->assertOk()->assertSee('Bienvenue sur');
        $this->get('/presentation')->assertOk()->assertSee('Tout ce dont votre ferme a besoin');
    }

    /**
     * Un utilisateur connecté qui suit un lien vers la présentation ne doit pas
     * recevoir une erreur : ces pages ne sont pas réservées aux visiteurs.
     */
    public function test_public_pages_stay_reachable_once_logged_in(): void
    {
        $this->actingAs($this->utilisateur());

        $this->get('/welcome')->assertOk();
        $this->get('/presentation')->assertOk();
    }

    /**
     * ⚠️ CHANGÉ LE 24/08/2026 : la racine mène à la CONNEXION, plus à la page
     * d'accueil publique. AgriERP est un outil de travail — un employé de la
     * ferme l'ouvre pour saisir une vente, pas pour lire une présentation.
     *
     * ⚠️ `/welcome` et `/presentation` restent servies : elles ne sont plus le
     * passage obligé, elles n'ont pas disparu. Les deux tests ci-dessus le
     * vérifient, et ce sont eux qui échoueraient si on les supprimait un jour
     * « puisque plus personne n'y passe ».
     */
    public function test_the_root_sends_a_visitor_to_the_login_page(): void
    {
        $this->get('/')->assertRedirect(route('login'));
    }

    public function test_the_public_pages_survive_the_root_change(): void
    {
        $this->get('/welcome')->assertOk();
        $this->get('/presentation')->assertOk();
    }

    /** Un utilisateur déjà connecté va droit à son espace de travail. */
    public function test_the_root_sends_a_logged_in_user_to_the_dashboard(): void
    {
        $this->actingAs($this->utilisateur());

        $this->get('/')->assertRedirect(route('dashboard.index'));
    }

    /** Les liens internes des pages publiques doivent résoudre réellement. */
    public function test_public_pages_link_to_real_routes(): void
    {
        $this->get('/welcome')
            ->assertSee(route('login'), false)
            ->assertSee(route('public.presentation'), false);

        $this->get('/presentation')
            ->assertSee(route('login'), false)
            ->assertSee(route('public.welcome'), false);
    }
}
