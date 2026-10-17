<?php

namespace Tests\Feature;

use Tests\TestCase;

/**
 * Ticket 15.4 (Sprint 15) — POLICES LOCALES ET PWA INSTALLABLE.
 *
 * Deux exigences client, verrouillées ici parce qu'elles sont toutes les
 * deux faciles à casser sans s'en apercevoir :
 *
 * 1. ⚠️ AUCUNE POLICE DISTANTE. Les deux layouts chargeaient Inter depuis
 *    `fonts.googleapis.com`. Sur une ferme d'Ikpinlè dont la liaison tombe,
 *    l'application s'affichait alors dans la police de secours du système —
 *    et chaque chargement de page attendait un serveur injoignable avant
 *    d'abandonner. Inter est désormais servie depuis `public/assets/fonts`.
 *
 *    Ce test échouerait si quelqu'un recollait un `<link>` Google Fonts en
 *    reprenant un bout de maquette : c'est exactement de cette façon que la
 *    dépendance était arrivée.
 *
 * 2. ⚠️ PWA INSTALLABLE. Un manifeste sans icône 192 ou 512, ou un
 *    `sw.js` absent, ne produit AUCUNE erreur visible : le navigateur cesse
 *    simplement de proposer l'installation, en silence. Seul un test peut
 *    signaler la régression.
 *
 * Aucun accès base de données : ces vérifications portent sur des fichiers.
 */
class PwaEtPolicesLocalesTest extends TestCase
{
    /** Les deux layouts de l'application. */
    private const LAYOUTS = [
        'resources/views/layouts/app.blade.php',
        'resources/views/layouts/guest.blade.php',
    ];

    private function lire(string $chemin): string
    {
        $absolu = base_path($chemin);
        $this->assertFileExists($absolu, "Fichier attendu absent : {$chemin}");

        return file_get_contents($absolu);
    }

    // =================================================================
    //  1. Polices
    // =================================================================

    public function test_aucune_vue_ne_charge_une_police_distante(): void
    {
        $fautifs = [];

        foreach (rglob(resource_path('views'), '*.blade.php') as $vue) {
            $contenu = file_get_contents($vue);

            // On ignore les commentaires Blade {{-- ... --}} : les docblocs de
            // ce projet CITENT « fonts.googleapis.com » pour expliquer pourquoi
            // il ne faut plus y toucher. Interdire la mention rendrait la
            // documentation impossible ; c'est la BALISE qui est interdite.
            $sansCommentaires = preg_replace('/\{\{--.*?--\}\}/s', '', $contenu);

            if (preg_match('/<link[^>]*(fonts\.googleapis\.com|fonts\.gstatic\.com)/i', $sansCommentaires)) {
                $fautifs[] = str_replace(base_path().DIRECTORY_SEPARATOR, '', $vue);
            }
        }

        $this->assertSame([], $fautifs,
            "Ces vues chargent une police depuis Google. Inter doit être servie ".
            "depuis public/assets/fonts (voir @font-face dans resources/css/app.css) :\n".
            implode("\n", $fautifs));
    }

    public function test_les_fichiers_de_police_declares_dans_le_css_existent(): void
    {
        $css = $this->lire('resources/css/app.css');

        preg_match_all('#url\("(/assets/fonts/[^"]+)"\)#', $css, $m);

        $this->assertNotEmpty($m[1], 'Aucun @font-face local trouvé dans app.css.');

        foreach (array_unique($m[1]) as $url) {
            $this->assertFileExists(
                public_path(ltrim($url, '/')),
                "Police déclarée dans app.css mais absente de public/ : {$url}"
            );
        }
    }

    public function test_inter_est_declaree_sur_tout_l_axe_de_graisse(): void
    {
        $css = $this->lire('resources/css/app.css');

        $this->assertStringContainsString('font-family: "Inter"', $css);

        // Inter est une police VARIABLE : un seul fichier couvre 100 à 900.
        // Déclarer `font-weight: 400` ferait synthétiser le gras par le
        // navigateur — les titres en 700/800 seraient déformés.
        $this->assertMatchesRegularExpression(
            '/font-family: "Inter";.*?font-weight: 100 900;/s',
            $css,
            'Le @font-face Inter doit déclarer `font-weight: 100 900` (police variable).'
        );
    }

    // =================================================================
    //  2. PWA
    // =================================================================

    public function test_le_manifeste_est_un_json_valide_et_complet(): void
    {
        $manifeste = json_decode($this->lire('public/manifest.webmanifest'), true);

        $this->assertIsArray($manifeste, 'manifest.webmanifest n\'est pas un JSON valide.');

        foreach (['name', 'short_name', 'start_url', 'scope', 'display', 'theme_color', 'icons'] as $cle) {
            $this->assertArrayHasKey($cle, $manifeste, "Clé obligatoire absente du manifeste : {$cle}");
        }

        $this->assertSame('standalone', $manifeste['display'],
            'Sans `display: standalone`, le navigateur ne propose pas l\'installation.');
    }

    public function test_le_manifeste_porte_les_icones_exigees_pour_l_installation(): void
    {
        $manifeste = json_decode($this->lire('public/manifest.webmanifest'), true);
        $tailles = array_column($manifeste['icons'], 'sizes');

        // Chrome refuse de proposer l'installation sans une 192 et une 512.
        $this->assertContains('192x192', $tailles);
        $this->assertContains('512x512', $tailles);

        $usages = array_column($manifeste['icons'], 'purpose');
        $this->assertContains('maskable', $usages,
            'Une icône `maskable` est nécessaire pour un rendu correct sur Android.');
    }

    public function test_chaque_icone_du_manifeste_existe_reellement(): void
    {
        $manifeste = json_decode($this->lire('public/manifest.webmanifest'), true);

        foreach ($manifeste['icons'] as $icone) {
            $this->assertFileExists(
                public_path(ltrim($icone['src'], '/')),
                "Icône déclarée au manifeste mais absente : {$icone['src']}"
            );
        }

        foreach ($manifeste['shortcuts'] ?? [] as $raccourci) {
            foreach ($raccourci['icons'] ?? [] as $icone) {
                $this->assertFileExists(public_path(ltrim($icone['src'], '/')));
            }
        }
    }

    public function test_le_service_worker_et_la_page_hors_ligne_existent(): void
    {
        $sw = $this->lire('public/sw.js');
        $this->lire('public/offline.html');

        // Garde-fou métier : le service worker ne doit JAMAIS intercepter
        // autre chose que des GET. Livewire pilote toute l'application par
        // des POST vers /livewire/update — les mettre en cache casserait la
        // moindre saisie (docbloc de sw.js, règle 1).
        $this->assertStringContainsString("request.method !== 'GET'", $sw,
            'sw.js doit ignorer toute requête non-GET.');
        $this->assertStringContainsString("'/livewire/'", $sw,
            'sw.js doit exclure explicitement les requêtes Livewire.');
    }

    public function test_chaque_fichier_precache_par_le_service_worker_existe(): void
    {
        $sw = $this->lire('public/sw.js');

        preg_match('/const SOCLE = \[(.*?)\];/s', $sw, $m);
        $this->assertNotEmpty($m, 'Liste SOCLE introuvable dans sw.js.');

        preg_match_all("#'(/[^']+)'#", $m[1], $fichiers);

        foreach ($fichiers[1] as $chemin) {
            $this->assertFileExists(
                public_path(ltrim($chemin, '/')),
                "Fichier précaché par sw.js mais absent de public/ : {$chemin}"
            );
        }
    }

    public function test_les_layouts_declarent_le_manifeste_et_la_fenetre_d_installation(): void
    {
        foreach (self::LAYOUTS as $layout) {
            $contenu = $this->lire($layout);

            $this->assertStringContainsString('manifest.webmanifest', $contenu,
                "{$layout} ne référence pas le manifeste : l'application ne sera pas installable.");
            $this->assertStringContainsString('theme-color', $contenu, $layout);
            $this->assertStringContainsString('apple-touch-icon', $contenu,
                "{$layout} : iOS ignore le manifeste pour l'icône, apple-touch-icon est obligatoire.");
            $this->assertStringContainsString('<x-pwa-install />', $contenu,
                "{$layout} n'affiche pas l'invitation à installer.");
            $this->assertStringContainsString("navigator.serviceWorker.register('/sw.js'", $contenu,
                "{$layout} n'enregistre pas le service worker.");
        }
    }

    public function test_la_fenetre_d_installation_est_bien_en_bas_a_gauche(): void
    {
        $vue = $this->lire('resources/views/components/pwa-install.blade.php');

        // ⚠️ Contrainte réelle, pas cosmétique : le conteneur de toasts occupe
        // le bas à DROITE avec z-index 200. Le ticket 14.28 a déjà corrigé un
        // défaut où ces toasts interceptaient les clics du bouton « Valider la
        // Vente » du POS. Placer cette fenêtre à droite recréerait le conflit.
        $this->assertStringContainsString('bottom-md left-md', $vue,
            "La fenêtre d'installation doit rester en bas à GAUCHE (les toasts occupent le bas à droite).");

        // Elle doit pouvoir être réduite, et se souvenir de ce choix.
        $this->assertStringContainsString('reduire()', $vue);
        $this->assertStringContainsString('agrierp_pwa_reduit', $vue);
        $this->assertStringContainsString('plusTard()', $vue);
    }

    public function test_la_page_de_connexion_ne_demande_aucune_ressource_distante(): void
    {
        $reponse = $this->get('/login');
        $reponse->assertOk();

        $html = $reponse->getContent();

        $this->assertStringNotContainsString('fonts.googleapis.com/css', $html,
            'La page de connexion charge encore une feuille de style Google Fonts.');
        $this->assertStringNotContainsString('https://fonts.gstatic.com', $html);
        $this->assertStringContainsString('manifest.webmanifest', $html);
    }
}

if (! function_exists('rglob')) {
    /** Parcours récursif — évite d'ajouter une dépendance pour trois lignes. */
    function rglob(string $dossier, string $motif): array
    {
        $resultats = [];
        $iterateur = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($dossier));

        foreach ($iterateur as $fichier) {
            if ($fichier->isFile() && fnmatch($motif, $fichier->getFilename())) {
                $resultats[] = $fichier->getPathname();
            }
        }

        return $resultats;
    }
}
