<?php

namespace Tests\Feature;

use Tests\TestCase;

/**
 * PWA-PERF — garde-fou sur la taille des assets compilés par Vite.
 *
 * Lit le manifeste Vite (`public/build/manifest.json`) et vérifie que les fichiers
 * principaux ne dépassent pas les seuils convenus. Échoue si le manifeste est absent
 * (npm run build doit avoir été exécuté avant la suite).
 */
class PerformanceAssetsTest extends TestCase
{
    private const SEUIL_JS_OCTETS  = 300 * 1024;   // 300 Ko non compressés
    private const SEUIL_CSS_OCTETS = 100 * 1024;   // 100 Ko non compressés

    private string $repertoireBuild;

    protected function setUp(): void
    {
        parent::setUp();
        $this->repertoireBuild = public_path('build');
    }

    public function test_le_manifeste_vite_existe(): void
    {
        $this->assertFileExists(
            $this->repertoireBuild . '/manifest.json',
            'Lancer `npm run build` avant la suite de tests (manifeste Vite absent).'
        );
    }

    public function test_app_js_sous_300_ko(): void
    {
        $chemin = $this->cheminAsset('resources/js/app.js');
        $taille = filesize($chemin);

        $this->assertLessThanOrEqual(
            self::SEUIL_JS_OCTETS,
            $taille,
            sprintf(
                'app.js dépasse le seuil de 300 Ko : %s Ko (fichier : %s)',
                number_format($taille / 1024, 1),
                basename($chemin)
            )
        );
    }

    public function test_app_css_sous_100_ko(): void
    {
        $chemin = $this->cheminAsset('resources/css/app.css');
        $taille = filesize($chemin);

        $this->assertLessThanOrEqual(
            self::SEUIL_CSS_OCTETS,
            $taille,
            sprintf(
                'app.css dépasse le seuil de 100 Ko : %s Ko (fichier : %s)',
                number_format($taille / 1024, 1),
                basename($chemin)
            )
        );
    }

    /** Résout le chemin absolu d'un asset à partir de sa clé dans le manifeste Vite. */
    private function cheminAsset(string $cle): string
    {
        $manifeste = json_decode(
            file_get_contents($this->repertoireBuild . '/manifest.json'),
            true,
            flags: JSON_THROW_ON_ERROR
        );

        $this->assertArrayHasKey(
            $cle,
            $manifeste,
            "Clé « {$cle} » absente du manifeste Vite — vérifier vite.config.js."
        );

        $fichier = $manifeste[$cle]['file'];

        return $this->repertoireBuild . '/' . $fichier;
    }
}
