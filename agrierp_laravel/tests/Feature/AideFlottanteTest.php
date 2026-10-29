<?php

namespace Tests\Feature;

use App\Livewire\Parametres\AssistantDemarrage;
use App\Models\CompanySetting;
use App\Models\Customer;
use App\Models\ModuleConfig;
use App\Models\User;
use App\Support\AideEcrans;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Route;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket AIDE-1 — BOUTON FLOTTANT D'AIDE, AIDE PAR ÉCRAN, RELANCE DE L'ASSISTANT, VISITE GUIDÉE.
 *
 * Décision du client : le bouton n'existe QUE si le module « Assistant de démarrage » est allumé (éteint par défaut).
 * Ces tests lisent le HTML réellement rendu (module allumé / éteint), les textes de `lang/fr/aide_ecrans.php` (source
 * unique web + poste) et les routes déclarées : l'AIDE EST COMPLÈTE si chaque écran authentifié a son entrée.
 *
 * ⚠️ Ce que ces tests NE voient PAS : le comportement JavaScript (ouverture du tiroir, placement du trou lumineux, focus,
 * flèches du clavier) — Alpine n'est jamais chargé par `Livewire::test()` / `get()`. La logique de placement est
 * couverte par `node --test tests/Js/aide-logique.test.mjs` ; le rendu réel reste à constater dans un navigateur.
 */
class AideFlottanteTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Routes GET authentifiées qui ne sont PAS un écran de `layouts/app` (pas de bouton d'aide, donc pas d'entrée) —
     * jamais une exclusion silencieuse.
     */
    private const SANS_MISE_EN_PAGE = [
        'login' => 'page de connexion (mise en page `guest`)',
        'session.verrou' => 'écran de verrouillage (mise en page `guest`)',
        'mot-de-passe.obligatoire' => 'changement forcé du mot de passe (mise en page `guest`)',
        'justificatifs.show' => 'flux d\'un fichier, pas un écran',
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
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

    private function allumer(bool $actif = true): void
    {
        ModuleConfig::definir(ModuleConfig::ASSISTANT_DEMARRAGE, $actif, null);
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Le module commande le bouton
    // -----------------------------------------------------------------------------------------------------------------

    public function test_module_eteint_aucun_bouton_d_aide(): void
    {
        $html = $this->actingAs($this->compte('admin'))->get('/dashboard')->assertOk()->getContent();

        $this->assertStringNotContainsString('aideFlottante', $html);
        $this->assertStringNotContainsString('data-aide="aide"', $html);
        $this->assertStringNotContainsString('Aide et visite guidée', $html);
        // L'ancien bouton « Visite guidée » inerte n'est pas revenu.
        $this->assertStringNotContainsString('Visite guidée', $html);
        $this->assertStringNotContainsString('relancer-assistant', $html);
    }

    public function test_module_allume_le_bouton_et_les_quatre_reperes_de_la_visite_sont_la(): void
    {
        $this->allumer();
        $html = $this->actingAs($this->compte('admin'))->get('/dashboard')->assertOk()->getContent();

        $this->assertStringContainsString('aideFlottante', $html);
        $this->assertStringContainsString('title="Aide et visite guidée"', $html);
        foreach (['aide', 'topbar', 'contenu', 'menu'] as $repere) {
            $this->assertSame(1, substr_count($html, 'data-aide="'.$repere.'"'), "repère data-aide=\"$repere\"");
        }
        // Les repères sont posés sur les bons éléments du layout.
        $this->assertMatchesRegularExpression('/<aside id="sidebar" data-aide="menu"/', $html);
        $this->assertMatchesRegularExpression('/<header data-aide="topbar"/', $html);
        $this->assertMatchesRegularExpression('/<div data-aide="contenu"/', $html);
        $this->assertMatchesRegularExpression('/<button type="button" data-aide="aide"/', $html);
        // Icône `help`, comme demandé.
        $this->assertMatchesRegularExpression('/data-aide="aide".*?>\s*<span class="material-symbols-outlined"[^>]*>help<\/span>/s', $html);
    }

    public function test_le_module_allume_le_bouton_est_la_pour_tous_les_roles_mais_la_relance_est_pour_l_administrateur(): void
    {
        $this->allumer();

        $admin = $this->actingAs($this->compte('admin'))->get('/dashboard')->getContent();
        $this->assertStringContainsString('aide-relancer', $admin);

        $caissier = $this->actingAs($this->compte('caissier'))->get('/dashboard')->assertOk()->getContent();
        $this->assertStringContainsString('data-aide="aide"', $caissier, 'le bouton est sur tous les écrans, pour tous les rôles');
        $this->assertStringContainsString('aide-visite', $caissier);
        $this->assertStringNotContainsString('aide-relancer', $caissier, 'la relance suit le droit de l\'assistant (manage-parametres)');
    }

    public function test_le_bouton_ne_chevauche_pas_acces_rapide(): void
    {
        $this->allumer();
        $html = $this->actingAs($this->compte('admin'))->get('/dashboard')->getContent();

        preg_match('/title="Accès rapide[^"]*"[^>]*style="bottom:(\d+)px;/', $html, $acces);
        preg_match('/data-aide="aide".*?style="bottom:(\d+)px; right:16px;"/s', $html, $aide);

        $this->assertNotEmpty($acces, 'bouton Accès rapide');
        $this->assertNotEmpty($aide, 'bouton d\'aide');
        // Boutons ronds de 48 px : le bouton d'aide est au-dessus, avec au moins 8 px d'écart.
        $this->assertGreaterThanOrEqual(48 + 8, (int) $aide[1] - (int) $acces[1]);
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Le panneau lit l'aide de la route
    // -----------------------------------------------------------------------------------------------------------------

    public function test_le_panneau_lit_l_aide_de_la_route_affichee(): void
    {
        $this->allumer();
        $admin = $this->compte('admin');

        foreach (['/dashboard', '/gestion-stocks', '/parametres-hub', '/comptabilite-hub'] as $chemin) {
            $attendu = trans('aide_ecrans.ecrans')[$chemin];
            $response = $this->actingAs($admin)->get($chemin)->assertOk();

            $response->assertSee($attendu['titre'], false)->assertSee('Aide de cet écran');
            foreach ($attendu['puces'] as $puce) {
                $response->assertSee(e($puce), false);
            }
            $this->assertStringContainsString('data-aide-generique="0"', $response->getContent(), $chemin);
        }
    }

    public function test_une_route_a_parametre_lit_l_aide_de_son_chemin_declare(): void
    {
        $this->allumer();
        $client = Customer::create(['name' => 'Client Aide', 'phone' => '+22997000000', 'is_active' => true]);

        $response = $this->actingAs($this->compte('admin'))->get('/clients/'.$client->id.'/profil')->assertOk();

        $attendu = trans('aide_ecrans.ecrans')['/clients/{customer}/profil'];
        $response->assertSee($attendu['titre'], false);
        $this->assertStringContainsString('data-aide-generique="0"', $response->getContent());
    }

    public function test_une_route_non_listee_recoit_l_aide_generique_jamais_un_panneau_vide(): void
    {
        $aide = AideEcrans::pour('/une-route-qui-n-existe-pas');

        $this->assertTrue($aide['generique']);
        $this->assertSame(trans('aide_ecrans.defaut.titre'), $aide['titre']);
        $this->assertGreaterThanOrEqual(3, count($aide['puces']));
        $this->assertSame(trans('aide_ecrans.ecrans')['/dashboard']['titre'], AideEcrans::pour('/dashboard')['titre']);
        $this->assertFalse(AideEcrans::pour('/dashboard')['generique']);
    }

    public function test_chaque_route_authentifiee_a_son_entree_et_chaque_entree_a_sa_route(): void
    {
        // Choix documenté : le repli générique protège l'utilisateur (jamais de panneau vide), mais il ne doit pas masquer
        // un oubli. Une route ajoutée sans aide fait donc ÉCHOUER ce test jusqu'à ce que son aide soit rédigée.
        $routes = [];
        foreach (Route::getRoutes() as $route) {
            $nom = $route->getName();
            if (! in_array('GET', $route->methods(), true) || $nom === null || isset(self::SANS_MISE_EN_PAGE[$nom])) {
                continue;
            }
            if (! collect($route->gatherMiddleware())->contains(fn ($m) => is_string($m) && ($m === 'auth' || str_starts_with($m, 'auth:')))) {
                continue;
            }
            foreach (['api/', 'livewire', 'sanctum', 'storage', '_dusk'] as $prefixe) {
                if (str_starts_with($route->uri(), $prefixe)) {
                    continue 2;
                }
            }
            $routes[] = '/'.ltrim($route->uri(), '/');
        }
        sort($routes);

        $this->assertGreaterThanOrEqual(50, count($routes), 'le parcours des routes ne trouve plus les écrans');

        $entrees = array_keys(trans('aide_ecrans.ecrans'));
        sort($entrees);

        $this->assertSame([], array_values(array_diff($routes, $entrees)), 'routes authentifiées SANS aide dans lang/fr/aide_ecrans.php');
        $this->assertSame([], array_values(array_diff($entrees, $routes)), 'entrées d\'aide qui ne correspondent à AUCUNE route');
    }

    public function test_chaque_aide_a_un_titre_et_de_trois_a_cinq_puces_courtes_sans_marqueur_en_dur(): void
    {
        foreach (trans('aide_ecrans.ecrans') + ['(défaut)' => trans('aide_ecrans.defaut')] as $chemin => $aide) {
            $this->assertNotSame('', trim($aide['titre']), $chemin);
            $nombre = count($aide['puces']);
            $this->assertGreaterThanOrEqual(3, $nombre, "$chemin : au moins 3 puces");
            $this->assertLessThanOrEqual(5, $nombre, "$chemin : au plus 5 puces");
            foreach ($aide['puces'] as $puce) {
                $this->assertNotSame('', trim($puce), $chemin);
                $this->assertLessThanOrEqual(260, mb_strlen($puce), "$chemin : puce trop longue : $puce");
                $this->assertStringNotContainsString('TODO', $puce);
            }
        }
    }

    public function test_la_visite_a_quatre_etapes_et_ses_libelles(): void
    {
        $visite = AideEcrans::visite();

        $this->assertCount(4, $visite['etapes']);
        foreach ($visite['etapes'] as $etape) {
            $this->assertNotSame('', trim($etape['titre']));
            $this->assertNotSame('', trim($etape['texte']));
        }
        $this->assertSame('Étape :numero sur :total', $visite['etape_sur']);
        $this->assertSame('Passer', $visite['passer']);

        // Le HTML rendu porte les 4 étapes, le bouton « Passer » et l'indicateur.
        $this->allumer();
        $html = $this->actingAs($this->compte('admin'))->get('/dashboard')->getContent();
        $this->assertStringContainsString('dusk="aide-passer"', $html);
        $this->assertStringContainsString('dusk="aide-indicateur"', $html);
        // La configuration passée à Alpine (`Js::from`) porte les 4 étapes du fichier de langue, mot pour mot, et les 4 repères.
        $this->assertSame(1, preg_match("/aideFlottante\\(JSON\\.parse\\('(.*?)'\\)\\)/s", $html, $m));
        // Le littéral JavaScript `'…'` se lit comme une chaîne JSON (\u0022, \\u00e9 : mêmes échappements) : on le décode deux fois.
        $config = json_decode(json_decode('"'.$m[1].'"'), true);
        $this->assertSame($visite['etapes'], $config['etapes']);
        $this->assertSame(['aide', 'topbar', 'contenu', 'menu'], $config['cibles']);
        $this->assertSame($visite['passer'], $config['libelles']['passer']);
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Relancer l'assistant de démarrage
    // -----------------------------------------------------------------------------------------------------------------

    public function test_relancer_l_assistant_ouvre_la_modale_meme_reportee_et_meme_terminee(): void
    {
        $this->allumer();
        $this->actingAs($this->compte('admin'));
        CompanySetting::current()->update(['onboarding_completed_at' => '2026-10-01 08:00:00']);
        session()->put(AssistantDemarrage::CLE_SESSION, true);   // « Plus tard » déjà cliqué

        Livewire::test(AssistantDemarrage::class, ['auto' => false])
            ->assertSet('afficher', false)
            ->dispatch('relancer-assistant')
            ->assertSet('afficher', true)
            ->assertDispatched('open-modal', name: 'modal-demarrage')
            ->assertSee('data-etape="entreprise"', false);

        // ⚠️ Jamais d'écriture : l'onboarding reste TERMINÉ en base.
        $this->assertSame('2026-10-01 08:00:00', CompanySetting::current()->onboarding_completed_at->format('Y-m-d H:i:s'));
    }

    public function test_relancer_est_ignore_sans_le_droit_ou_module_eteint(): void
    {
        $this->allumer();
        $this->actingAs($this->compte('caissier'));
        Livewire::test(AssistantDemarrage::class, ['auto' => false])->dispatch('relancer-assistant')->assertSet('afficher', false);

        $this->allumer(false);
        $this->actingAs($this->compte('admin'));
        Livewire::test(AssistantDemarrage::class, ['auto' => false])->dispatch('relancer-assistant')->assertSet('afficher', false);
    }

    public function test_terminer_apres_une_relance_ne_reecrit_pas_la_date_de_fin(): void
    {
        $this->allumer();
        $this->actingAs($this->compte('admin'));
        CompanySetting::current()->update(['onboarding_completed_at' => '2026-10-01 08:00:00']);
        // Toutes les étapes obligatoires sont en place : « Terminer » est autorisé.
        $this->mock(\App\Services\DemarrageService::class, function ($m) {
            $m->shouldReceive('obligatoiresFaites')->andReturn(true);
            $m->shouldReceive('etapes')->andReturn([]);
        });

        Livewire::test(AssistantDemarrage::class, ['auto' => false])->dispatch('relancer-assistant')->call('terminer');

        $this->assertSame('2026-10-01 08:00:00', CompanySetting::current()->onboarding_completed_at->format('Y-m-d H:i:s'));
    }

    public function test_l_assistant_est_monte_sur_tous_les_ecrans_mais_ne_s_ouvre_seul_que_sur_le_tableau_de_bord(): void
    {
        $this->allumer();
        $admin = $this->compte('admin');   // base vide : des étapes obligatoires manquent

        // Tableau de bord : monté ET ouvert (comportement d'avant).
        $this->actingAs($admin)->get('/dashboard')->assertOk()
            ->assertSeeLivewire(AssistantDemarrage::class)->assertSee('data-etape="entreprise"', false);

        // Autre écran : monté (pour « Relancer »), mais fermé.
        $this->actingAs($admin)->get('/gestion-stocks')->assertOk()
            ->assertSeeLivewire(AssistantDemarrage::class)->assertDontSee('data-etape="entreprise"', false);

        // Module éteint : ni l'un ni l'autre.
        $this->allumer(false);
        $this->actingAs($admin)->get('/gestion-stocks')->assertOk()->assertDontSeeLivewire(AssistantDemarrage::class);
    }

    public function test_le_bouton_relancer_envoie_l_evenement_que_l_assistant_ecoute(): void
    {
        $js = file_get_contents(resource_path('js/aide.js'));
        $assistant = file_get_contents(app_path('Livewire/Parametres/AssistantDemarrage.php'));

        $this->assertStringContainsString("window.Livewire.dispatch('relancer-assistant')", $js);
        $this->assertStringContainsString("#[On('relancer-assistant')]", $assistant);
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Gardes de code : navigation sans rechargement, aucune bibliothèque, classes statiques
    // -----------------------------------------------------------------------------------------------------------------

    public function test_le_javascript_de_l_aide_ne_pose_aucun_ecouteur_global_ni_bibliotheque(): void
    {
        foreach (['aide.js', 'aide-logique.js'] as $fichier) {
            $js = file_get_contents(resource_path('js/'.$fichier));

            // Le seul `addEventListener` permis : `alpine:init`, une fois au chargement du module (comme verrou.js).
            preg_match_all('/addEventListener\(\s*([^,)]+)/', $js, $appels);
            foreach ($appels[1] as $evenement) {
                $this->assertSame("'alpine:init'", trim($evenement), "$fichier : écouteur global « $evenement » (se cumulerait à chaque page avec wire:navigate)");
            }
            $this->assertDoesNotMatchRegularExpression('/import\s+Alpine|Alpine\.start\(/', $js, "$fichier : Alpine est démarré par Livewire");
            $this->assertDoesNotMatchRegularExpression('#https?://#', $js, "$fichier : aucune ressource externe");
            $this->assertDoesNotMatchRegularExpression('/cdnjs|unpkg|jsdelivr|googleapis/i', $js);
        }
        $this->assertStringContainsString("import './aide';", file_get_contents(resource_path('js/app.js')));
    }

    public function test_le_composant_n_a_ni_ressource_externe_ni_lien_sans_wire_navigate_ni_classe_construite(): void
    {
        $vue = file_get_contents(resource_path('views/components/aide-flottante.blade.php'));

        $this->assertDoesNotMatchRegularExpression('#(src|href)="https?://#', $vue);
        $this->assertDoesNotMatchRegularExpression('/<a\s+(?!wire:navigate)[^>]*href="\//', $vue);
        // Les événements de la fenêtre sont des directives Alpine (retirées avec la page), pas du JavaScript posé à la main.
        $this->assertStringContainsString('x-on:keydown.escape.window', $vue);
        $this->assertStringContainsString('x-on:resize.window', $vue);
        // Tailwind : aucune classe concaténée (`'bg-'.$x`, `bg-{{ … }}`).
        $this->assertDoesNotMatchRegularExpression('/class="[^"]*\{\{/', $vue);
        // Dans `#app-racine` : le verrou de session rend le composant inerte avec la page.
        $layout = file_get_contents(resource_path('views/layouts/app.blade.php'));
        $this->assertLessThan(strpos($layout, '<x-verrou-session'), strpos($layout, '<x-aide-flottante'));
        $this->assertSame(1, substr_count($layout, 'id="app-racine"'));
    }
}
