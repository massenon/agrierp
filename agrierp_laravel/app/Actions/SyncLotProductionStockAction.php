<?php

namespace App\Actions;

use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;

/**
 * Ticket 14.37 (Sprint 14) — LA PRODUCTION DU CHEPTEL ENTRE EN STOCK.
 *
 * 🔴 DÉFAUT RÉVÉLÉ PAR LA SIMULATION (ticket 14.31) : une naissance augmentait
 * l'effectif d'une bande, mais aucun flux ne faisait entrer le sujet en stock
 * vendable. Une exploitation qui élève ses propres animaux ne pouvait donc
 * jamais les vendre au-delà de son inventaire d'ouverture — constaté sur la
 * simulation, où les ventes s'arrêtaient net faute de marchandise.
 *
 * Le prototype montre pourtant la ligne attendue dans son journal des
 * mouvements : « Lapereau sevré | Entrée | **Naissance** | +6 ».
 *
 * MOUVEMENTS RÉPERCUTÉS, ET EUX SEULS :
 *     + naissances       le sujet devient une marchandise
 *     − mortalité        il cesse d'en être une
 *     − dons             il quitte l'exploitation
 *
 * ⚠️ ACHATS ET VENTES DÉLIBÉRÉMENT EXCLUS — ils sont DÉJÀ comptés ailleurs, et
 * les recompter ici doublerait chaque mouvement :
 *   - un achat de sujets passe par `EnregistrerAchat`, qui appelle déjà
 *     `AdjustStockAction` sur le produit acheté ;
 *   - une vente passe par le POS, qui décrémente le stock PUIS écrit la vente
 *     dans la fiche via `recordFicheVente()` (ticket 14.4).
 * La fiche journalière porte donc des colonnes dont deux sont le REFLET d'un
 * mouvement déjà enregistré, et deux seulement en sont la source.
 *
 * ⚠️ CALCUL DIFFÉRENTIEL, jamais absolu. Une fiche se corrige : l'éleveur
 * revient sur sa journée et rectifie une mortalité. Appliquer les valeurs
 * telles quelles à chaque enregistrement compterait la production autant de
 * fois que la fiche est sauvegardée. On applique donc l'ÉCART entre l'état
 * précédent et le nouveau — ce qui lève au passage la limitation documentée
 * dans `FichePondeuses` (« à traiter par un recalcul différentiel si un besoin
 * réel émerge »).
 *
 * ⚠️ SANS PRODUIT RATTACHÉ À LA BANDE, RIEN NE SE PRODUIT. Le rattachement est
 * une décision de l'exploitant (champ « Produit issu de cette bande »), pas une
 * déduction : une espèce correspond à plusieurs produits, et deux bandes de
 * même espèce peuvent avoir des destinations différentes.
 */
class SyncLotProductionStockAction
{
    /**
     * @param  array{ne?: int, mort?: int, don?: int}  $avant  état de la fiche avant
     *                                                         enregistrement (vide si création)
     */
    public function execute(LivestockDailyEntry $entree, array $avant = []): void
    {
        $lot = $entree->lot ?? LivestockLot::find($entree->lot_id);

        if (! $lot || ! $lot->product_id) {
            return;   // bande non rattachée à un produit : aucun mouvement
        }

        $produit = $lot->product;

        if (! $produit) {
            return;
        }

        $deltaAvant = $this->soldeProduction($avant['ne'] ?? 0, $avant['mort'] ?? 0, $avant['don'] ?? 0);
        $deltaApres = $this->soldeProduction((int) $entree->ne, (int) $entree->mort, (int) ($entree->don ?? 0));

        $ajustement = $deltaApres - $deltaAvant;

        if ($ajustement === 0) {
            return;   // rien n'a changé : pas de mouvement fantôme au journal
        }

        app(AdjustStockAction::class)->execute(
            $produit,
            (float) $ajustement,
            'elevage',
            $lot->id,
            $entree->entry_date,
            'Production '.$lot->code.' — naissances et pertes du '.$entree->entry_date->format('d/m/Y'),
        );
    }

    /** Solde de production d'une journée : ce que le cheptel apporte au stock. */
    private function soldeProduction(int $nes, int $morts, int $dons): int
    {
        return $nes - $morts - $dons;
    }
}
