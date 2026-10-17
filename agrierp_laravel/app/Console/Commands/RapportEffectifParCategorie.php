<?php

namespace App\Console\Commands;

use App\Services\EffectifParCategorieService;
use Illuminate\Console\Command;

/**
 * Ticket 15.39 — RAPPORT À BLANC de l'effectif par catégorie (lapins et porcs).
 *
 * LECTURE SEULE : aucune écriture en base, aucun recalcul appliqué. Liste par bande les fiches, la
 * tête de chaîne éventuelle (départ saisi, ou départ implicite D6 NON écrit), le nombre de fiches
 * dont les catégories changeraient, et les bandes sans historique.
 */
class RapportEffectifParCategorie extends Command
{
    protected $signature = 'elevage:effectif-categories-rapport';

    protected $description = 'Rapport à blanc (lecture seule) : chaînes d\'effectif par catégorie des bandes lapins et porcs.';

    public function handle(EffectifParCategorieService $service): int
    {
        $rapport = $service->rapportABlanc();

        $this->table(
            ['Bande', 'Espèce', 'Fiches', 'Statut', 'Tête (date)', 'Après tête', 'Calculables', 'À modifier'],
            array_map(fn ($b) => [
                $b['code'], $b['espece'], $b['fiches'], $b['statut'], $b['tete']['date'] ?? '—',
                $b['fiches_apres_tete'], $b['calculables'], $b['a_modifier'],
            ], $rapport['bandes']),
        );

        foreach ($rapport['bandes'] as $b) {
            foreach (array_filter([$b['refus'], ...$b['avertissements']]) as $message) {
                $this->warn("{$b['code']} : {$message}");
            }
        }

        $r = $rapport['resume'];
        $this->info("Chaînes : {$r['chaine']} — têtes implicites (non écrites) : {$r['tete_implicite']} — non ventilées : {$r['non_ventilee']} — sans historique : {$r['sans_historique']}.");
        $this->line('Rapport à blanc : aucune écriture effectuée.');

        return self::SUCCESS;
    }
}
