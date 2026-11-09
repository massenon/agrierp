<?php

namespace Tests\Feature\Concerns;

use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;

/**
 * Ticket VOL-2 — fixtures des tests génériques. Depuis VOL-2, une bande d'aviculture au stade « ponte » entre dans la chaîne
 * des volailles pondeuses : son effectif de DÉPART par stade est obligatoire avant toute journée (fiche, vente, transformation,
 * entrée de sujets). Les tests dont l'objet est AUTRE (caisse, interblocage, synchronisation…) posent ce départ en une ligne
 * plutôt que de contourner le refus : une première fiche, à zéro mouvement, qui porte l'effectif de la bande.
 */
trait AvecDepartPondeuses
{
    /**
     * Pose le départ (début de [$jour]) sur une fiche à zéro mouvement. Par défaut tout l'effectif initial est « Pondeuse » ;
     * [$repartition] = [Poussin ponte, Poussin en croissance, Poulette, Pondeuse] pour un départ réparti.
     *
     * @param  array{int, int, int, int}|null  $repartition
     */
    protected function departPondeuses(LivestockLot $lot, string $jour, ?array $repartition = null): LivestockDailyEntry
    {
        [$pp, $pc, $pl, $po] = $repartition ?? [0, 0, 0, (int) $lot->initial_quantity];

        return LivestockDailyEntry::create([
            'lot_id' => $lot->id, 'entry_date' => $jour,
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0, 'effectif_final' => $pp + $pc + $pl + $po,
            'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 0, 'mort_4' => 0,
            'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0, 'don_4' => 0,
            'vente_repro' => 0, 'vente_sevre' => 0, 'vente_jeune' => 0, 'vente_4' => 0,
            'passage_4_sevre' => 0, 'passage_sevre_jeune' => 0, 'passage_jeune_repro' => 0,
            'cat_depart_repro' => $po, 'cat_depart_sevre' => $pc, 'cat_depart_jeune' => $pl, 'cat_depart_4' => $pp,
            'cat_eff_repro' => $po, 'cat_eff_sevre' => $pc, 'cat_eff_jeune' => $pl, 'cat_eff_4' => $pp,
        ]);
    }
}
