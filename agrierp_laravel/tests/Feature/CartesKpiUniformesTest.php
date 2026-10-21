<?php

namespace Tests\Feature;

use Tests\TestCase;

/**
 * GARDE-FOU — « les tailles des cartes KPI doivent être uniformes partout » (demande client, web ET poste).
 *
 * Toute carte KPI du web porte la classe commune `kpi-card` (app.css : marge p-md, liseré gauche de 4 px, hauteur
 * minimale de 112 px — la même valeur que `CarteKpi.hauteurMin` du poste). Une carte recopiée à la main avec ses
 * propres `p-md` / `border-l-4` finit par diverger : ce test l'interdit.
 */
class CartesKpiUniformesTest extends TestCase
{
    /** @return array<string, string> chemin => contenu */
    private function vues(): array
    {
        $out = [];
        $it = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator(resource_path('views'), \FilesystemIterator::SKIP_DOTS));
        foreach ($it as $f) {
            if (str_ends_with($f->getFilename(), '.blade.php')) {
                $out[$f->getPathname()] = file_get_contents($f->getPathname());
            }
        }

        return $out;
    }

    public function test_la_classe_commune_fixe_la_hauteur_minimale_la_marge_et_le_liseré(): void
    {
        $css = file_get_contents(resource_path('css/app.css'));

        $this->assertMatchesRegularExpression('/\.kpi-card\s*\{[^}]*min-height:\s*112px[^}]*\}/', $css);
        $this->assertMatchesRegularExpression('/\.kpi-card\s*\{[^}]*padding:\s*16px[^}]*\}/', $css);
        $this->assertMatchesRegularExpression('/\.kpi-card\s*\{[^}]*border-left-width:\s*4px[^}]*\}/', $css);
    }

    public function test_le_composant_kpi_card_porte_la_classe_commune(): void
    {
        $composant = file_get_contents(resource_path('views/components/kpi-card.blade.php'));

        $this->assertStringContainsString("'kpi-card ", $composant);
        $this->assertStringNotContainsString('p-sm lg:p-md', $composant, 'La marge vient de `kpi-card`, pas d\'une variante locale.');
    }

    public function test_aucune_carte_kpi_recopiee_sans_la_classe_commune(): void
    {
        $fautives = [];
        foreach ($this->vues() as $chemin => $contenu) {
            // Un `<div>` à fond blanc, bordure et liseré gauche coloré : c'est une carte KPI.
            preg_match_all('/<div\s[^>]*class="([^"]*border-l-(?:brand|info|error|accent)-[^"]*)"/', $contenu, $m);
            foreach ($m[1] as $classes) {
                if (! str_contains($classes, 'kpi-card') || preg_match('/(^|\s)(p-md|p-sm|border-l-4)(\s|$)/', $classes)) {
                    $fautives[] = basename($chemin).' : '.$classes;
                }
            }
        }

        $this->assertSame([], $fautives, 'Toute carte KPI porte `kpi-card` et ni `p-md` ni `border-l-4` locaux.');
    }
}
