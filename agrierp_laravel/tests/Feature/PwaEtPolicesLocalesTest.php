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

    // =================================================================
    //  3. PWA-1 (08/11/2026) — caisse hors ligne : les NOUVELLES règles
    //     (aucune des gardes ci-dessus n'est retirée ; chacune est ici
    //     doublée d'une garde plus précise)
    // =================================================================

    /** Le corps d'un tableau JavaScript `const NOM = [ ... ];` de sw.js, en liste de chaînes. */
    private function listeDuWorker(string $nom): array
    {
        preg_match('/const '.$nom.' = \[(.*?)\];/s', $this->lire('public/sw.js'), $m);
        $this->assertNotEmpty($m, "Liste {$nom} introuvable dans sw.js.");
        preg_match_all("#'([^']+)'#", $m[1], $valeurs);

        return $valeurs[1];
    }

    public function test_le_service_worker_garde_ses_trois_regles_de_surete_en_tete_mot_pour_mot(): void
    {
        $sw = $this->lire('public/sw.js');

        // Avant PWA-1, seules les règles 1 et 3 étaient vérifiées « de loin » : la règle 2 (aucun HTML authentifié) n'était
        // assertée nulle part. Elle l'est maintenant, par son intitulé ET par son code.
        $this->assertStringContainsString('1. SEULES LES REQUÊTES `GET` SONT INTERCEPTÉES.', $sw);
        $this->assertStringContainsString("2. AUCUNE PAGE HTML AUTHENTIFIÉE N'EST STOCKÉE.", $sw);
        $this->assertStringContainsString('3. SEULS LES FICHIERS STATIQUES SONT MIS EN CACHE', $sw);
        $this->assertStringContainsString("if (request.method !== 'GET') return;", $sw);
    }

    public function test_les_sept_chemins_jamais_touches_sont_exactement_ceux_de_la_doctrine(): void
    {
        $this->assertEqualsCanonicalizing(
            ['/livewire/', '/api/', '/login', '/logout', '/reset-password', '/broadcasting/', '/storage/'],
            $this->listeDuWorker('EXCLUS'),
            'EXCLUS de sw.js ne doit ni perdre un chemin ni en gagner un sans décision écrite.'
        );
        $sw = $this->lire('public/sw.js');
        $this->assertStringContainsString("EXCLUS.some((p) => url.pathname.startsWith(p))", $sw);
        // Aucune requête portant un en-tête Authorization n'est jamais interceptée.
        $this->assertStringContainsString("request.headers.has('Authorization')", $sw);
    }

    public function test_seules_deux_pages_html_statiques_peuvent_etre_en_cache_et_toute_ecriture_passe_par_la_garde(): void
    {
        $sw = $this->lire('public/sw.js');

        // PWA-4 (11/11/2026) : trois pages de consultation hors ligne ajoutées à HTML_STATIQUES.
        // Toutes sont purement statiques (sans session, sans données de la ferme) : règle 2 respectée.
        $this->assertSame(
            ['/offline.html', '/caisse-hors-ligne.html', '/offline-stock.html', '/offline-creances.html', '/offline-ventes.html'],
            $this->listeDuWorker('HTML_STATIQUES'),
            'Toute page HTML en cache doit être STATIQUE (sans donnée utilisateur ni session). ' .
            'Ajouter une page authentifiée ici casserait la règle 2 de sw.js.'
        );

        // La garde unique refuse tout HTML hors de cette liste, tout JSON, toute requête authentifiée.
        $this->assertMatchesRegularExpression("/text\\/html'\\) && !HTML_STATIQUES\\.includes\\(url\\.pathname\\)\\) return false;/", $sw);
        $this->assertStringContainsString("includes('json')) return false;", $sw);
        $this->assertStringContainsString("requete.headers.has('Authorization')) return false;", $sw);

        // Chaque écriture dans un cache (hors installation et purge) est précédée de `peutEtreStocke` : on compte.
        $ecritures = preg_match_all('/\.put\(/', $sw);
        $gardes = preg_match_all('/if \(peutEtreStocke\(request, url, reponse\)\)/', $sw);
        $this->assertGreaterThan(0, $ecritures);
        $this->assertSame($ecritures, $gardes, 'Toute écriture de cache doit passer par peutEtreStocke().');

        // Le worker n'appelle jamais l'API ni Livewire : il ne voit aucune donnée métier.
        $this->assertDoesNotMatchRegularExpression("#fetch\\([^)]*['\"]/(api|livewire)#", $sw);
        // L'envoi des ventes n'est PAS fait par le worker : l'événement `sync` ne fait que réveiller un onglet.
        preg_match("/addEventListener\\('sync'.*?\\n\\}\\);/s", $sw, $sync);
        $this->assertNotEmpty($sync, "Gestionnaire 'sync' introuvable.");
        $this->assertStringNotContainsString('fetch(', $sync[0]);
        $this->assertStringContainsString("postMessage({ type: 'SYNCHRONISER' })", $sync[0]);
    }

    public function test_la_version_du_cache_a_ete_incrementee_et_la_purge_est_prevue(): void
    {
        $sw = $this->lire('public/sw.js');

        preg_match("/const VERSION = 'agrierp-v(\\d+)';/", $sw, $m);
        $this->assertNotEmpty($m);
        $this->assertGreaterThanOrEqual(6, (int) $m[1], 'PWA-1 change des fichiers précachés : VERSION doit avoir passé v5.');

        // `activate` supprime tout cache d'une autre version ; la déconnexion les supprime TOUS.
        $this->assertStringContainsString('noms.filter((n) => !n.startsWith(VERSION)).map((n) => caches.delete(n))', $sw);
        $this->assertStringContainsString("event.data.type === 'PURGER'", $sw);
        $this->assertMatchesRegularExpression('/caches\.keys\(\)\.then\(\(noms\) => Promise\.all\(noms\.map\(\(n\) => caches\.delete\(n\)\)\)\)/', $sw);
    }

    public function test_l_enveloppe_de_la_caisse_est_precachee_et_l_installation_ignore_le_cache_http(): void
    {
        $socle = $this->listeDuWorker('SOCLE');
        foreach (['/offline.html', '/caisse-hors-ligne.html', '/assets/hors-ligne/caisse.js', '/assets/hors-ligne/caisse-style.css'] as $fichier) {
            $this->assertContains($fichier, $socle);
        }
        $this->assertStringContainsString("new Request(u, { cache: 'reload' })", $this->lire('public/sw.js'));
    }

    public function test_la_page_de_caisse_est_statique_sans_aucune_donnee_ni_session(): void
    {
        $html = $this->lire('public/caisse-hors-ligne.html');
        $sansCommentaires = preg_replace('/<!--.*?-->/s', '', $html);

        foreach (['{{', '@csrf', 'csrf-token', '<livewire', 'wire:', 'x-data', '@if', '@foreach', 'Bearer '] as $interdit) {
            $this->assertStringNotContainsString($interdit, $sansCommentaires, "La page statique ne doit contenir ni gabarit ni donnée ({$interdit}).");
        }
        // Aucun nom d'utilisateur, de client ni de produit : un seul script, à elle, et des ressources locales.
        preg_match_all('/(?:src|href)="([^"]+)"/', $sansCommentaires, $liens);
        foreach ($liens[1] as $lien) {
            $this->assertMatchesRegularExpression('#^/(assets/|manifest\.webmanifest|mode-hors-ligne)#', $lien, "Ressource inattendue : {$lien}");
        }
        $this->assertSame(1, preg_match_all('/<script/', $sansCommentaires));
        $this->assertStringContainsString('type="module" src="/assets/hors-ligne/caisse.js"', $sansCommentaires);
        $this->assertStringNotContainsString('fonts.googleapis.com', $html);
    }

    public function test_les_libelles_de_la_caisse_hors_ligne_sont_ceux_de_la_vue_blade_qui_est_le_maitre(): void
    {
        $blade = $this->lire('resources/views/livewire/ventes/pos-interface.blade.php');
        $html = $this->lire('public/caisse-hors-ligne.html');

        foreach ([
            'Panier de Vente', 'Sous-total', 'Total à Payer', 'Remise (FCFA)', 'Mode de Règlement', 'Montant Reçu', 'Monnaie à Rendre',
            'Client Anonyme', 'Type de Facture', 'Vente à la Pièce', 'Montant Global de la Vente (FCFA)', 'Nombre de sujets / Quantité',
            'Ajouter au panier', 'Rechercher un produit...', 'Tous', 'Facture Normalisée', 'IFU du client', 'Nom et prénom du client *',
            'Taux AIB', 'Aucun produit trouvé.', 'Sélectionnez un produit pour commencer.', 'Crédit / À terme', 'Virement bancaire',
            'Mobile Money', 'Espèces', 'Modifier les informations de facturation', 'Laissez vide pour un client sans IFU (client particulier).',
            "Le montant de l'AIB est calculé par la DGI.",
        ] as $libelle) {
            $this->assertStringContainsString($libelle, $blade, "« {$libelle} » n'est plus dans la caisse du web : la vue Blade est le maître.");
            $this->assertStringContainsString($libelle, $html, "« {$libelle} » manque à la caisse hors ligne.");
        }

        // Les libellés de statut reprennent ceux de la modale « Synchronisation » du poste.
        $dart = $this->lire('../agrierp_flutter/lib/core/sync/modale_synchronisation.dart');
        foreach (['En attente d', 'Refusés par le serveur', 'Synchroniser maintenant'] as $libelle) {
            $this->assertStringContainsString($libelle, $dart, $libelle);
        }
        $this->assertStringContainsString('Synchroniser maintenant', $html);
        $this->assertStringContainsString("En attente d\\'envoi", file_get_contents(base_path('resources/js/hors-ligne/catalogue.js')));
    }

    public function test_le_javascript_de_la_caisse_ne_stocke_rien_en_clair_et_n_inventera_aucun_protocole(): void
    {
        foreach (glob(base_path('resources/js/hors-ligne/*.js')) as $fichier) {
            $js = file_get_contents($fichier);
            $nom = basename($fichier);
            // Jamais de jeton, de mot de passe ni de PIN dans localStorage / sessionStorage : seuls deux marqueurs sans secret.
            $this->assertStringNotContainsString('sessionStorage', $js, $nom);
            $this->assertDoesNotMatchRegularExpression('/localStorage\.setItem\(\s*[\'"][^\'"]*(token|jeton|pin|password|mot)/i', $js, $nom);
            // Un seul protocole : les routes existantes des postes, aucune autre route d'API.
            preg_match_all("#['\"`](/api/[a-z/\\-]+)#", $js, $routes);
            foreach ($routes[1] as $route) {
                $this->assertContains($route, ['/api/auth/login', '/api/auth/logout', '/api/sync/pull', '/api/sync/push'], "{$nom} appelle une route non prévue : {$route}");
            }
            $this->assertDoesNotMatchRegularExpression('/Alpine\.start\(\)/', $js, "{$nom} : pas de Alpine.start()");
            $this->assertDoesNotMatchRegularExpression('#https?://(?!www\.w3\.org)#', $js, "{$nom} : aucune ressource externe");
        }
    }

    public function test_la_construction_de_la_caisse_est_branchee_au_build(): void
    {
        $this->assertStringContainsString('vite build --config vite.hors-ligne.config.js', $this->lire('package.json'));
        $this->lire('vite.hors-ligne.config.js');
        $this->assertFileExists(public_path('assets/hors-ligne/caisse.js'), 'Lancez `npm run build` : la caisse hors ligne est un fichier construit.');
        $this->assertFileExists(public_path('assets/hors-ligne/caisse-style.css'));
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
