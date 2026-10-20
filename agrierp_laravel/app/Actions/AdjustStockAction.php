<?php

namespace App\Actions;

use App\Models\Product;
use App\Models\StockMovement;
use App\Services\InventaireAuComptageService;

/**
 * Ticket 6.1 (Sprint 6) — point d'entrée UNIQUE pour tout changement de
 * `products.stock_qty` (Document AVOID_INSTRUCTIONS.md § Difficult
 * Debugging : un seul point de vérité par mécanisme partagé). Applique
 * l'ajustement ET journalise le mouvement dans `stock_movements` — les
 * deux effets sont désormais indissociables, jamais l'un sans l'autre.
 *
 * Type déterminé par le signe de `$delta` (entree si positif, sortie si
 * négatif) — les ajustements manuels (ticket 6.2, `AjustementsStock`)
 * passent `$referenceType = 'adjustment'` et se filtrent sur ce champ à
 * l'affichage, jamais sur le type lui-même.
 *
 * ⚠️ RÉTRO-CÂBLAGE RÉALISÉ DANS CE MÊME TICKET : les 8 points d'appel
 * existants qui modifiaient `stock_qty` directement (`increment`/
 * `decrement` bruts, Sprints 3-5 : POS, Achats, Transformation, Retours,
 * Bons de Commande, Annulation de vente, Production d'œufs) sont
 * réécrits pour passer par cette action — sans ce rétro-câblage,
 * l'historique des mouvements (ticket 6.2) démarrerait vide pour tout ce
 * qui a précédé ce ticket, un gap significatif découvert et corrigé
 * immédiatement plutôt que laissé pour plus tard.
 */
class AdjustStockAction
{
    public function execute(
        Product $product,
        float $delta,
        string $referenceType,
        ?string $referenceId = null,
        ?\DateTimeInterface $movementDate = null,
        ?string $reason = null,
    ): StockMovement {
        // 🔴→✅ TICKET EX5 (EF5, R4) — UN EXERCICE CLOS EST EN LECTURE SEULE, LE STOCK COMPRIS. Un ajout de stock daté du
        // 20/12/2026 était accepté le 15/03/2027 alors que 2026 était clôturé (web et poste) : le stock de 2026, figé par
        // son inventaire de clôture, bougeait après coup. Le refus vient ICI, avant toute écriture, pour tout mouvement
        // (ajout, inventaire, fiche, et ceux des ventes ou achats, déjà refusés par leur écriture comptable).
        app(\App\Services\AccountingEntryService::class)->refuserSiExerciceClos(
            ($movementDate ?? now())->format('Y-m-d')
        );

        if ($delta > 0) {
            $product->increment('stock_qty', $delta);
        } elseif ($delta < 0) {
            $product->decrement('stock_qty', abs($delta));
        }

        $mouvement = StockMovement::create([
            'product_id' => $product->id,
            'type' => $delta >= 0 ? 'entree' : 'sortie',
            'quantity' => abs($delta),
            'reference_type' => $referenceType,
            'reference_id' => $referenceId,
            'reason' => $reason,
            'movement_date' => $movementDate ?? now(),
        ]);

        // 🔴→✅ TICKET S-T12 — UN MOUVEMENT DATÉ AVANT UN COMPTAGE DÉJÀ ENREGISTRÉ (vente d'une caisse restée hors ligne,
        // achat du poste, vente antidatée au web) : le comptage le reflétait déjà. Une régularisation d'inventaire datée
        // du comptage le neutralise après lui, dans ce même appel (`InventaireAuComptageService`). Un mouvement sans date
        // (daté de maintenant) ne précède aucun comptage : rien à chercher.
        if ($movementDate !== null) {
            app(InventaireAuComptageService::class)->compenserMouvementAnterieur($product, $mouvement);
        }

        return $mouvement;
    }
}
