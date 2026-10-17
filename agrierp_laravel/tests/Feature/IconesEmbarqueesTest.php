<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * Ticket 15.6 — LA FONTE D'ICÔNES EST RÉDUITE AUX ICÔNES RÉELLEMENT EMPLOYÉES.
 *
 * ⚠️⚠️ CE QUE CE CONTRÔLE PROTÈGE. `MaterialSymbolsOutlined.woff2` pesait
 * 3,87 Mo — 4271 icônes pour moins de 200 employées, soit 94 % de la charge
 * réseau de la page de connexion. Le sous-ensemble embarqué tombe à 37 Ko,
 * mais il a un coût : une icône ajoutée à une vue SANS être ajoutée à la liste
 * ne s'affiche plus du tout — elle apparaît sous la forme de son propre nom en
 * toutes lettres (« inventory_2 » au milieu du tableau). Le défaut n'est
 * visible qu'à l'œil, sur la page concernée, et jamais en test de rendu.
 *
 * Ce contrôle relève les icônes de DEUX sources que l'outil de fabrication ne
 * peut pas croiser seul :
 *   • le code (vues, composants, JavaScript) ;
 *   • la BASE — `livestock_species.icon` et `notifications.icon` portent des
 *     noms d'icônes qui n'existent dans aucun fichier du dépôt.
 *
 * Régénérer la fonte après ajout : `python outils/sous_ensemble_icones.py`.
 */
class IconesEmbarqueesTest extends TestCase
{
    private const LISTE = 'resources/fonts/icones-embarquees.json';

    /** @return array<int, string> */
    private function embarquees(): array
    {
        return json_decode(file_get_contents(base_path(self::LISTE)), true);
    }

    public function test_the_subset_font_is_served_and_stays_small(): void
    {
        $fonte = public_path('assets/fonts/MaterialSymbolsOutlined.woff2');

        $this->assertFileExists($fonte);

        // ⚠️ SEUIL VOLONTAIREMENT BAS : la fonte complète fait 3 960 036 octets.
        // Si quelqu'un la recopie par-dessus le sous-ensemble — le geste le plus
        // naturel du monde en cas de doute — le contrôle doit le dire.
        $this->assertLessThan(
            200 * 1024,
            filesize($fonte),
            'La fonte servie dépasse 200 Ko : la fonte complète a probablement '
            .'été remise en place. Relancez outils/sous_ensemble_icones.py.'
        );
    }

    /**
     * ⚠️ La fonte complète ne doit PAS être servie : elle reste dans
     * `resources/fonts/` comme source de fabrication, hors de `public/`.
     */
    public function test_the_complete_font_is_not_public(): void
    {
        $this->assertFileExists(base_path('resources/fonts/MaterialSymbolsOutlined-complete.woff2'));
        $this->assertFileDoesNotExist(public_path('assets/fonts/MaterialSymbolsOutlined-complete.woff2'));
    }

    /**
     * ⚠️⚠️ AUCUNE FONTE NE VIENT D'INTERNET, ET C'EST UNE EXIGENCE MÉTIER.
     * La liaison de la ferme tombe régulièrement : une page dont le texte
     * attend `fonts.googleapis.com` reste blanche jusqu'au dépassement du
     * délai. Les trois fontes sont servies depuis `public/assets/fonts`.
     */
    public function test_no_font_or_script_is_fetched_from_the_internet(): void
    {
        foreach (['/login', '/welcome', '/presentation'] as $chemin) {
            $html = $this->get($chemin)->assertOk()->getContent();

            foreach (['fonts.googleapis.com', 'fonts.gstatic.com', 'cdn.tailwindcss.com'] as $origine) {
                $this->assertStringNotContainsString(
                    $origine,
                    $html,
                    "$chemin appelle $origine : la page dépend d'internet pour s'afficher."
                );
            }
        }
    }

    public function test_every_icon_written_in_the_code_is_embedded(): void
    {
        $embarquees = $this->embarquees();
        $manquantes = [];

        foreach ($this->fichiersSources() as $fichier) {
            $contenu = file_get_contents($fichier);

            preg_match_all(
                '/material-symbols-outlined[^>]*>\s*([a-z0-9_]{2,40})\s*</i',
                $contenu,
                $trouvees
            );

            foreach ($trouvees[1] as $icone) {
                if (! in_array($icone, $embarquees, true)) {
                    $manquantes[$icone] = str_replace(base_path().DIRECTORY_SEPARATOR, '', $fichier);
                }
            }
        }

        $this->assertSame(
            [],
            $manquantes,
            "Ces icônes sont écrites dans une vue mais absentes du sous-ensemble : "
            .json_encode($manquantes, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)
        );
    }

    /**
     * ⚠️⚠️ LES ICÔNES DE LA BASE NE SONT DANS AUCUN FICHIER. Une espèce créée
     * en production avec `icon = 'agriculture'` s'afficherait en toutes lettres
     * si le nom ne figure pas dans le sous-ensemble — et rien dans le dépôt ne
     * l'aurait signalé.
     */
    public function test_every_icon_stored_in_the_database_is_embedded(): void
    {
        $embarquees = $this->embarquees();
        $manquantes = [];

        foreach ([['livestock_species', 'icon'], ['notifications', 'icon']] as [$table, $colonne]) {
            if (! Schema::hasTable($table) || ! Schema::hasColumn($table, $colonne)) {
                continue;
            }

            foreach (DB::table($table)->whereNotNull($colonne)->distinct()->pluck($colonne) as $icone) {
                if ($icone !== '' && ! in_array($icone, $embarquees, true)) {
                    $manquantes[$icone] = $table.'.'.$colonne;
                }
            }
        }

        $this->assertSame([], $manquantes, 'Icônes en base absentes du sous-ensemble : '
            .json_encode($manquantes, JSON_UNESCAPED_UNICODE));
    }

    /** @return array<int, string> */
    private function fichiersSources(): array
    {
        $fichiers = [];

        foreach ([base_path('resources/views'), base_path('resources/js'), public_path('assets/js')] as $dossier) {
            if (! is_dir($dossier)) {
                continue;
            }

            $iterateur = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($dossier));
            foreach ($iterateur as $fichier) {
                if ($fichier->isFile() && preg_match('/\.(blade\.php|js)$/', $fichier->getFilename())) {
                    $fichiers[] = $fichier->getPathname();
                }
            }
        }

        return $fichiers;
    }
}
