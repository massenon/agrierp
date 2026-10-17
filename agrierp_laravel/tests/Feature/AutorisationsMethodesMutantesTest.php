<?php

namespace Tests\Feature;

use Tests\TestCase;

/**
 * Ticket S2 — TOUTE MÉTHODE LIVEWIRE QUI ÉCRIT COMMENCE PAR UNE AUTORISATION.
 *
 * 🔴 Le balayage 14.64 avait protégé 42 méthodes ; il en restait 27 qui écrivaient en base sans `authorize()`,
 * dont les cinq `saveDay()` des fiches d'élevage, l'annulation d'une vente, les devis, le pointage et la
 * sauvegarde déclenchée depuis Rôles & Permissions. La route ne demande souvent qu'un droit de LECTURE
 * (`can:view-elevage`) : un rôle de consultation pouvait donc écrire.
 *
 * ⚠️ CE TEST LIT LE CODE SOURCE, et c'est voulu : une méthode ajoutée demain sans autorisation fonctionne
 * parfaitement à l'écran, aucun test de rendu ne la verrait.
 */
class AutorisationsMethodesMutantesTest extends TestCase
{
    /**
     * Méthodes volontairement sans `authorize()` : elles agissent sur l'utilisateur lui-même ou s'exécutent
     * avant authentification (même liste que le ticket 14.64).
     */
    private const EXCLUSIONS = [
        'Auth/ResetPassword.php::submit',
        'Notifications/Index.php::markAsRead',
        'Notifications/Index.php::delete',
        'Profil/MonProfil.php::updatePassword',
        'Shared/NotificationBell.php::markAsRead',
    ];

    /** Appels qui écrivent en base (ou déclenchent une écriture). */
    private const ECRITURES = '/->(save|create|update|delete|increment|decrement|forceDelete|restore)\(|::create\(|::(updateOrCreate|firstOrCreate)\(|->execute\(|Artisan::call|DB::table/';

    public function test_aucune_methode_livewire_n_ecrit_sans_autorisation(): void
    {
        $racine = app_path('Livewire');
        $fautives = [];

        $fichiers = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($racine));
        foreach ($fichiers as $fichier) {
            if ($fichier->getExtension() !== 'php') {
                continue;
            }

            $source = file_get_contents($fichier->getPathname());
            $relatif = str_replace('\\', '/', substr($fichier->getPathname(), strlen($racine) + 1));

            preg_match_all('/public function (\w+)\s*\([^)]*\)\s*(?::\s*[\w\\\\?]+)?\s*\{/', $source, $methodes, PREG_OFFSET_CAPTURE);

            foreach ($methodes[1] as $i => [$nom]) {
                if (preg_match('/^(mount|render|boot|hydrate|dehydrate|rules|messages|get[A-Z]|updated)/', $nom)) {
                    continue;
                }

                $corps = $this->corps($source, $methodes[0][$i][1] + strlen($methodes[0][$i][0]));

                if (preg_match(self::ECRITURES, $corps)
                    && ! preg_match('/authorize|abort_unless/', $corps)
                    && ! in_array($relatif.'::'.$nom, self::EXCLUSIONS, true)) {
                    $fautives[] = $relatif.'::'.$nom;
                }
            }
        }

        $this->assertSame([], $fautives, "Méthodes qui écrivent sans autorisation :\n".implode("\n", $fautives));
    }

    public function test_les_cinq_fiches_d_elevage_exigent_manage_elevage_avant_d_enregistrer(): void
    {
        foreach (['FicheEscargots', 'FicheLapins', 'FichePondeuses', 'FichePorcs', 'FicheReproducteurs'] as $fiche) {
            $source = file_get_contents(app_path("Livewire/Elevage/{$fiche}.php"));

            $this->assertMatchesRegularExpression(
                "/public function saveDay\(\)[^{]*\{\s*\\\$this->authorize\('manage-elevage'\);/",
                $source,
                "{$fiche}::saveDay doit commencer par authorize('manage-elevage')",
            );
        }
    }

    private function corps(string $source, int $debut): string
    {
        $profondeur = 1;
        $i = $debut;
        $longueur = strlen($source);

        while ($profondeur > 0 && $i < $longueur) {
            $profondeur += match ($source[$i]) {
                '{' => 1,
                '}' => -1,
                default => 0,
            };
            $i++;
        }

        return substr($source, $debut, $i - $debut);
    }
}
