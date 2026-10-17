<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Route;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use Tests\TestCase;

/**
 * Ticket 14.29 (Sprint 14) — AUDIT STATIQUE : 0 lien cassé, 0 ressource absente.
 *
 * Les audits existants parcourent les routes (`AuditToutesLesRoutesTest`) et la
 * console du navigateur (`AuditConsoleNavigateurTest`). Aucun ne vérifiait ce
 * qui casse le plus discrètement : un `route('nom')` pointant vers une route
 * supprimée ou jamais créée, un `<x-composant>` sans fichier, un `asset()` vers
 * un fichier absent de `public/`.
 *
 * ⚠️ Une route inexistante référencée dans une vue lève une
 * `RouteNotFoundException` **au rendu**, pas au démarrage : elle ne se
 * manifeste que le jour où un utilisateur ouvre l'écran concerné — et
 * seulement si le lien est dans une branche `@if` réellement empruntée. Un
 * audit de routes qui charge chaque page ne l'attrape donc pas
 * systématiquement. Ce contrôle-ci est exhaustif par construction.
 *
 * ⚠️ LES COMMENTAIRES BLADE SONT RETIRÉS AVANT ANALYSE. Ce projet documente
 * abondamment ses décisions dans des blocs `{{-- --}}`, qui citent des noms de
 * routes futures (« seront migrés vers `route('module.index')` ») et des
 * composants explicitement écartés (« ne jamais confondre avec `<x-app-layout>` »).
 * Les analyser produirait trois faux positifs permanents — et un audit qui
 * signale du bruit finit ignoré.
 */
class AuditLiensEtRessourcesTest extends TestCase
{
    /** @return array<int, string> */
    private function vues(): array
    {
        $vues = [];
        $iterateur = new RecursiveIteratorIterator(new RecursiveDirectoryIterator(resource_path('views')));

        foreach ($iterateur as $fichier) {
            if ($fichier->isFile() && str_ends_with($fichier->getFilename(), '.blade.php')) {
                $vues[] = str_replace('\\', '/', $fichier->getPathname());
            }
        }

        sort($vues);

        return $vues;
    }

    /** Source débarrassée de ses commentaires Blade et HTML. */
    private function sourceUtile(string $chemin): string
    {
        $src = file_get_contents($chemin);
        $src = preg_replace('/\{\{--.*?--\}\}/s', '', $src);

        return preg_replace('/<!--.*?-->/s', '', $src);
    }

    private function relatif(string $chemin): string
    {
        return str_replace(str_replace('\\', '/', base_path()).'/', '', $chemin);
    }

    /** Aucun `route('nom')` d'une vue ne doit pointer vers une route inexistante. */
    public function test_no_view_links_to_a_route_that_does_not_exist(): void
    {
        $noms = [];

        foreach (Route::getRoutes() as $route) {
            if ($route->getName()) {
                $noms[] = $route->getName();
            }
        }

        $casses = [];

        foreach ($this->vues() as $vue) {
            if (! preg_match_all("/route\(\s*'([a-zA-Z0-9_.\-]+)'/", $this->sourceUtile($vue), $trouves)) {
                continue;
            }

            foreach (array_unique($trouves[1]) as $nom) {
                if (! in_array($nom, $noms, true)) {
                    $casses[] = $this->relatif($vue)." -> route('".$nom."')";
                }
            }
        }

        $this->assertSame([], array_values(array_unique($casses)),
            'Liens casses : ces vues referencent des routes qui n existent pas.');
    }

    /** Tout `<x-composant>` doit avoir un fichier de vue correspondant. */
    public function test_every_blade_component_referenced_actually_exists(): void
    {
        $manquants = [];

        foreach ($this->vues() as $vue) {
            if (! preg_match_all('/<x-([a-zA-Z0-9._\-]+)/', $this->sourceUtile($vue), $trouves)) {
                continue;
            }

            foreach (array_unique($trouves[1]) as $composant) {
                if (str_starts_with($composant, 'slot')) {
                    continue;
                }

                $chemin = str_replace('.', '/', $composant);

                $existe = file_exists(resource_path('views/components/'.$chemin.'.blade.php'))
                    || file_exists(resource_path('views/components/'.$chemin.'/index.blade.php'));

                if (! $existe) {
                    $manquants[] = $this->relatif($vue).' -> <x-'.$composant.'>';
                }
            }
        }

        $this->assertSame([], array_values(array_unique($manquants)),
            'Composants Blade references sans fichier correspondant.');
    }

    /** Tout `asset('chemin')` littéral doit exister dans `public/`. */
    public function test_every_referenced_asset_exists_in_public(): void
    {
        $absents = [];

        foreach ($this->vues() as $vue) {
            if (! preg_match_all("/asset\(\s*'([^']+)'/", $this->sourceUtile($vue), $trouves)) {
                continue;
            }

            foreach (array_unique($trouves[1]) as $chemin) {
                // Chemins construits dynamiquement : non vérifiables statiquement.
                if (str_contains($chemin, '{') || str_contains($chemin, '$')) {
                    continue;
                }

                if (! file_exists(public_path(ltrim($chemin, '/')))) {
                    $absents[] = $this->relatif($vue)." -> asset('".$chemin."')";
                }
            }
        }

        $this->assertSame([], array_values(array_unique($absents)),
            'Ressources referencees absentes de public/.');
    }

    /** @return array<int, string> */
    private function sourcesPhp(): array
    {
        $fichiers = [];
        $iterateur = new RecursiveIteratorIterator(new RecursiveDirectoryIterator(app_path()));

        foreach ($iterateur as $fichier) {
            if ($fichier->isFile() && str_ends_with($fichier->getFilename(), '.php')) {
                $fichiers[] = str_replace('\\', '/', $fichier->getPathname());
            }
        }

        sort($fichiers);

        return $fichiers;
    }

    /**
     * Source PHP débarrassée de ses commentaires — mêmes raisons que pour les
     * vues : les docblocs de ce projet citent abondamment des noms de routes et
     * de vues, y compris ceux d'écrans encore à construire.
     */
    private function phpUtile(string $chemin): string
    {
        $src = preg_replace('#/\*.*?\*/#s', '', file_get_contents($chemin));

        return preg_replace('#//.*$#m', '', $src);
    }

    /**
     * Les composants Livewire redirigent eux aussi vers des routes nommées :
     * une route supprimée y casserait une action (et non un simple lien), sans
     * que rien ne le signale avant le clic.
     */
    public function test_no_php_class_redirects_to_a_route_that_does_not_exist(): void
    {
        $noms = [];

        foreach (Route::getRoutes() as $route) {
            if ($route->getName()) {
                $noms[] = $route->getName();
            }
        }

        $casses = [];

        foreach ($this->sourcesPhp() as $fichier) {
            if (! preg_match_all("/route\(\s*'([a-zA-Z0-9_.\-]+)'/", $this->phpUtile($fichier), $trouves)) {
                continue;
            }

            foreach (array_unique($trouves[1]) as $nom) {
                if (! in_array($nom, $noms, true)) {
                    $casses[] = $this->relatif($fichier)." -> route('".$nom."')";
                }
            }
        }

        $this->assertSame([], array_values(array_unique($casses)),
            'Classes PHP referencant des routes inexistantes.');
    }

    /**
     * Tout `view('x.y')` d'un composant ou d'un contrôleur doit exister : une
     * vue renommée ne se manifeste qu'au rendu de l'écran concerné.
     */
    public function test_every_view_referenced_from_php_exists(): void
    {
        $manquantes = [];

        foreach ($this->sourcesPhp() as $fichier) {
            if (! preg_match_all("/view\(\s*'([a-zA-Z0-9_.\-]+)'/", $this->phpUtile($fichier), $trouves)) {
                continue;
            }

            foreach (array_unique($trouves[1]) as $vue) {
                if (! file_exists(resource_path('views/'.str_replace('.', '/', $vue).'.blade.php'))) {
                    $manquantes[] = $this->relatif($fichier)." -> view('".$vue."')";
                }
            }
        }

        $this->assertSame([], array_values(array_unique($manquantes)),
            'Vues referencees depuis PHP sans fichier correspondant.');
    }

    /**
     * Toute route nommée doit pointer vers une cible réellement instanciable —
     * un composant Livewire supprimé laisserait une route qui n'échoue qu'au
     * moment où quelqu'un l'ouvre.
     */
    public function test_every_named_route_targets_an_existing_class(): void
    {
        $introuvables = [];

        foreach (Route::getRoutes() as $route) {
            $action = $route->getActionName();

            if ($action === 'Closure' || ! $route->getName()) {
                continue;
            }

            $classe = explode('@', $action)[0];

            if (! class_exists($classe)) {
                $introuvables[] = $route->getName().' -> '.$classe;
            }
        }

        $this->assertSame([], array_values(array_unique($introuvables)),
            'Routes pointant vers une classe inexistante.');
    }
}
