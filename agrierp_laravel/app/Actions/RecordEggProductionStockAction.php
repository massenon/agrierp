<?php

namespace App\Actions;

use App\Models\LivestockDailyEntry;
use App\Services\EggStockLedgerService;

/**
 * Ticket 14.59 (Sprint 14) — LA PONTE DU JOUR INCRÉMENTE LE STOCK D'ŒUFS.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  ⚠️⚠️ POURQUOI CETTE ACTION EXISTE : UNE PONTE SAISIE AU POSTE N'ENTRAIT
 *  NULLE PART
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * La maquette `fiche-volailles-pondeuses.html` l'annonce en toutes lettres :
 * « **Incrémentation Automatique du Stock : +14 Plateaux au Stock Produits** ».
 * L'écran Livewire le faisait — mais le code vivait **à l'intérieur** de
 * `FichePondeuses::saveDay()`, donc inatteignable depuis la synchronisation.
 *
 * Une fiche de ponte saisie hors ligne sur un poste arrivait donc au serveur
 * comme une **ligne morte** : `ponte_total` renseigné, et pas un seul œuf au
 * stock. Exactement le défaut déjà corrigé pour les ventes hors ligne
 * (ticket 14.52) — un enregistrement qui existe mais ne produit aucun de ses
 * effets se remarque des semaines plus tard, à l'inventaire.
 *
 * ⚠️ **LE GARDE-FOU EST L'ESPÈCE ET LE STADE, PAS LA PRÉSENCE DE `ponte_total`.**
 * Cette colonne est aussi renseignée par les fiches Reproducteurs et Escargots,
 * qui n'incrémentent AUCUN stock produit — leurs œufs ne sont pas des œufs de
 * table. Déclencher sur la seule présence du champ ferait entrer des œufs à
 * couver et des pontes d'escargots dans le stock commercial.
 *
 * ⚠️ **À LA CRÉATION SEULEMENT, JAMAIS À LA MODIFICATION.** Limitation connue
 * et volontaire, héritée du ticket 6.1 : incrémenter à chaque enregistrement
 * compterait plusieurs fois les mêmes œufs lors d'une simple correction du
 * même jour. Elle protège aussi le renvoi d'une fiche dont le poste n'a pas eu
 * l'accusé de réception : l'upsert retrouve l'enregistrement, donc aucun
 * doublon de stock. Corriger une fiche déjà enregistrée ne réajuste pas le
 * stock — un recalcul différentiel reste à construire si le besoin émerge.
 */
class RecordEggProductionStockAction
{
    public function __construct(
        private readonly EggStockLedgerService $grandLivre,
        private readonly AdjustStockAction $ajusterStock,
    ) {
    }

    /**
     * @return int Nombre de plateaux réellement entrés en stock.
     */
    public function execute(LivestockDailyEntry $fiche): int
    {
        $lot = $fiche->lot()->with('species')->first();

        // ⚠️ Œufs de TABLE uniquement : aviculture au stade ponte.
        if (! $lot || $lot->stage !== 'ponte' || $lot->species?->code !== 'aviculture') {
            return 0;
        }

        $commercialisables = max(0, (int) $fiche->ponte_total - (int) $fiche->ponte_casses);
        $plateaux = $this->grandLivre->enPlateaux($commercialisables)['plateaux'];

        $produit = $this->grandLivre->eggProduct();

        if ($produit === null || $plateaux <= 0) {
            return 0;
        }

        // ⚠️ Le mouvement est daté du JOUR DE LA FICHE, pas de l'instant de la
        // synchronisation : une ponte du 3 poussée le 7 doit peser sur le
        // stock du 3, sinon le grand livre des œufs — qui borne le stock
        // reporté strictement avant la date consultée — la compterait deux
        // fois ou pas du tout.
        $this->ajusterStock->execute(
            $produit,
            (float) $plateaux,
            'daily_entry',
            $fiche->id,
            \Carbon\Carbon::parse($fiche->entry_date),
        );

        return $plateaux;
    }
}
