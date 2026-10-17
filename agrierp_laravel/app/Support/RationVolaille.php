<?php

namespace App\Support;

use Illuminate\Support\Collection;
use Illuminate\Support\Str;

/**
 * Ticket 15.57 — RATIONNEMENT DES FICHES AVICOLES (Pondeuses, Reproducteurs), commun au web et au poste
 * (`ration_volaille.dart`, même règle).
 *
 * Ces fiches ne portent pas d'effectif par stade : seul le total de la bande est connu. La règle, déjà celle du
 * poste depuis F0.30 et désormais celle du web (sections présentes des deux côtés, décision client du 17/10/2026) :
 *  - les lignes sont celles du barème `feed_ration_standards` de l'aviculture, dans l'ordre de leur libellé ;
 *  - l'effectif final du jour va à la PREMIÈRE ligne dont le libellé contient la clé de la fiche (« pondeuse »
 *    pour la fiche Pondeuses, qui ne liste que des bandes au stade « ponte » ; « reproducteur » pour la fiche
 *    Reproducteurs), 0 aux autres ;
 *  - ⚠️ AUCUNE LIGNE NE CORRESPOND (le barème du semis n'a pas de ligne « reproducteur ») : effectifs et total
 *    « — » avec la raison, JAMAIS une provende de 0 g qui se lirait « rien servi ».
 */
class RationVolaille
{
    public const PONDEUSE = 'pondeuse';

    public const REPRODUCTEUR = 'reproducteur';

    /**
     * @param  Collection<int, object>  $rations  lignes de `feed_ration_standards` (aviculture)
     * @return array{lignes: array<int, array{libelle: string, ration: float, effectif: ?int, total_g: ?float}>, total_g: ?float, total_kg: ?float, rattachee: bool}
     */
    public static function tableau(Collection $rations, string $cle, int $effectif): array
    {
        $triees = $rations->sortBy('stage_label', SORT_STRING)->values();
        $rang = $triees->search(fn ($r) => str_contains(Str::lower(Str::ascii(trim((string) $r->stage_label))), $cle));
        $rattachee = $rang !== false;

        $lignes = $triees->map(function ($r, $i) use ($rang, $rattachee, $effectif) {
            $n = $rattachee ? ($i === $rang ? $effectif : 0) : null;
            $ration = (float) $r->ration_g_per_day;

            return ['libelle' => $r->stage_label, 'ration' => $ration, 'effectif' => $n, 'total_g' => $n === null ? null : $n * $ration];
        })->all();

        $total = $rattachee ? array_sum(array_column($lignes, 'total_g')) : null;

        return [
            'lignes' => $lignes,
            'total_g' => $total,
            'total_kg' => $total === null ? null : round($total / 1000, 2),
            'rattachee' => $rattachee,
        ];
    }
}
