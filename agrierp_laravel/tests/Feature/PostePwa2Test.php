<?php

namespace Tests\Feature;

use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket PWA-2 — LE POSTE FLUTTER COMPILÉ POUR LE WEB, servi sous /poste/ (portée distincte de `public/sw.js`).
 *
 * Les gardes de PwaEtPolicesLocalesTest (sw.js : GET seulement, aucun HTML authentifié, sept chemins exclus) ne sont PAS
 * retirées ; ce fichier ajoute les règles précises du service worker du poste (`agrierp_flutter/web/poste_sw.js`), du MIME
 * wasm, de l'absence de COOP/COEP et de l'absence de cache long sur les pages authentifiées.
 */
class PostePwa2Test extends TestCase
{
    use RefreshDatabase;

    private function lire(string $chemin): string
    {
        $absolu = base_path($chemin);
        $this->assertFileExists($absolu, "Fichier attendu absent : {$chemin}");

        return file_get_contents($absolu);
    }

    public function test_le_service_worker_du_poste_garde_ses_regles_de_surete(): void
    {
        $sw = $this->lire('../agrierp_flutter/web/poste_sw.js');

        $this->assertStringContainsString("requete.method !== 'GET'", $sw, 'Jamais un POST.');
        $this->assertStringContainsString("requete.headers.has('Authorization')", $sw, 'Jamais une réponse authentifiée.');
        $this->assertStringContainsString("if (!url.pathname.startsWith(PORTEE)) return;", $sw);
        $this->assertStringContainsString("if (!navigation && !PRECACHE.has(cle)) return;", $sw, 'Hors liste précachée : réseau, sans cache.');

        preg_match('/const INTERDITS = \[(.*?)\];/s', $sw, $m);
        $this->assertNotEmpty($m, 'Liste INTERDITS introuvable.');
        preg_match_all("#'([^']+)'#", $m[1], $valeurs);
        foreach (['/api/', '/livewire/', '/login', '/logout', '/sanctum/', '/storage/'] as $chemin) {
            $this->assertContains($chemin, $valeurs[1], "Le poste ne doit jamais servir ni garder {$chemin}.");
        }

        // Aucune écriture de cache hors installation (`addAll`) : le worker ne stocke jamais une réponse reçue.
        $this->assertDoesNotMatchRegularExpression('/\.put\(/', $sw, 'poste_sw.js ne doit jamais appeler cache.put().');
        $this->assertDoesNotMatchRegularExpression("#fetch\\([^)]*['\"]/(api|livewire)#", $sw);
        // Pas de skipWaiting automatique : seulement sur message.
        $this->assertSame(1, preg_match_all('/skipWaiting\(\)/', $sw), 'skipWaiting() seulement dans le gestionnaire de message.');
        $this->assertStringContainsString("evenement.data === 'SKIP_WAITING'", $sw);
        // Versionnage et purge des anciens caches.
        $this->assertStringContainsString("const VERSION = '@@VERSION@@'", $sw);
        $this->assertStringContainsString('n.startsWith(PREFIXE_CACHE) && n !== CACHE', $sw);
        $this->assertStringContainsString("{ cache: 'reload' }", $sw);
    }

    public function test_la_mise_a_jour_du_poste_est_controlee_jamais_forcee(): void
    {
        $boot = $this->lire('../agrierp_flutter/web/flutter_bootstrap.js');

        // PWA-2b : bandeau « Nouvelle version disponible — Recharger », hors du canevas Flutter.
        $this->assertStringContainsString('Nouvelle version disponible', $boot);
        $this->assertStringContainsString('Recharger', $boot);
        // SKIP_WAITING n'est envoyé QUE par le clic du bouton ; le rechargement n'a lieu qu'après ce clic.
        $this->assertSame(1, preg_match_all("/postMessage\('SKIP_WAITING'\)/", $boot), 'SKIP_WAITING seulement au clic.');
        $this->assertSame(1, preg_match_all('/location\.reload\(\)/', $boot), 'Un seul rechargement, conditionné au clic.');
        $this->assertMatchesRegularExpression('/if \(window\.__rechargerApresMiseAJour\) window\.location\.reload\(\)/', $boot);
        // Une première installation n'est pas une mise à jour.
        $this->assertStringContainsString('navigator.serviceWorker.controller', $boot);
        // Jamais de désinscription ni de service worker de Flutter.
        $this->assertStringNotContainsString('.unregister(', $boot);
        $this->assertStringNotContainsString("register('flutter_service_worker", $boot);
    }

    public function test_le_service_worker_du_poste_a_sa_propre_portee_et_n_empiete_pas_sur_sw_js(): void
    {
        $sw = $this->lire('../agrierp_flutter/web/poste_sw.js');
        $this->assertStringContainsString("new URL('./', self.location).pathname", $sw, 'La portée vient de son emplacement (/poste/).');

        $racine = $this->lire('public/sw.js');
        $this->assertStringNotContainsString('/poste/', $racine, 'sw.js (portée /) ne doit pas gérer /poste/.');

        $bootstrap = $this->lire('../agrierp_flutter/web/flutter_bootstrap.js');
        $this->assertStringContainsString("register('poste_sw.js', { scope: './' })", $bootstrap);
        $this->assertStringNotContainsString('serviceWorkerSettings', $bootstrap, 'Le service worker de Flutter (stub qui se désinscrit) reste désactivé.');
    }

    public function test_la_page_du_poste_est_statique_et_le_manifeste_a_la_portee_poste(): void
    {
        $html = $this->lire('../agrierp_flutter/web/index.html');
        foreach (['{{', '@csrf', 'csrf-token', 'Bearer ', 'wire:'] as $interdit) {
            $this->assertStringNotContainsString($interdit, $html, "index.html doit rester STATIQUE ({$interdit}).");
        }
        $this->assertStringContainsString('<title>LogiAgriERP</title>', $html);
        $this->assertStringContainsString('<base href="$FLUTTER_BASE_HREF">', $html);
        $this->assertStringNotContainsString('fonts.googleapis.com', $html);

        $m = json_decode($this->lire('../agrierp_flutter/web/manifest.json'), true);
        $this->assertSame('/poste/', $m['scope']);
        $this->assertSame('/poste/', $m['start_url']);
        $this->assertSame('standalone', $m['display']);
        foreach ($m['icons'] as $icone) {
            $this->assertFileExists(base_path('../agrierp_flutter/web/'.$icone['src']));
        }
    }

    public function test_apache_sert_wasm_avec_le_bon_type_et_ne_pose_ni_coop_ni_coep(): void
    {
        $htaccess = $this->lire('public/.htaccess');

        $this->assertStringContainsString('AddType application/wasm .wasm', $htaccess,
            'Sans application/wasm, le navigateur refuse sqlite3.wasm et canvaskit.wasm (écran vide).');
        $this->assertStringContainsString('"expr=%{REQUEST_URI} =~ m#^/poste/#"', $htaccess);
        $this->assertStringContainsString('Service-Worker-Allowed "/poste/"', $htaccess);
        $this->assertStringContainsString('Header set Cache-Control "no-cache"', $htaccess);

        // Aucune DIRECTIVE COOP/COEP (les commentaires peuvent les citer) : avec elles, drift passe en OPFS (≈ 150 s au tirage).
        $this->assertDoesNotMatchRegularExpression('/^\s*Header\s+[^#\n]*Cross-Origin-(Opener|Embedder)-Policy/mi', $htaccess);
        foreach (['app', 'bootstrap', 'config', 'routes'] as $dossier) {
            foreach (new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator(base_path($dossier))) as $f) {
                if ($f->isFile() && $f->getExtension() === 'php') {
                    $this->assertStringNotContainsString('Cross-Origin-Opener-Policy', file_get_contents($f->getPathname()), $f->getPathname());
                    $this->assertStringNotContainsString('Cross-Origin-Embedder-Policy', file_get_contents($f->getPathname()), $f->getPathname());
                }
            }
        }
    }

    public function test_le_dossier_du_poste_construit_est_ignore_par_git(): void
    {
        $this->assertStringContainsString('/public/poste', $this->lire('.gitignore'));
    }

    public function test_aucune_page_authentifiee_n_est_servie_avec_un_cache_long(): void
    {
        $this->seed(RolesAndPermissionsSeeder::class);
        $u = User::create(['name' => 'Admin', 'username' => 'admin', 'email' => 'admin@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $u->assignRole('admin');

        foreach ([$this->get('/login'), $this->actingAs($u)->get('/dashboard')] as $reponse) {
            $reponse->assertOk();
            $entete = (string) $reponse->headers->get('Cache-Control');
            $this->assertStringNotContainsString('public', $entete);
            $this->assertDoesNotMatchRegularExpression('/max-age=[1-9]/', $entete, "Cache long sur une page : {$entete}");
            $this->assertDoesNotMatchRegularExpression('/s-maxage/', $entete);
        }
    }
}
