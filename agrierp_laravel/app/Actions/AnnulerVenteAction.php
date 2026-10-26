<?php

namespace App\Actions;

use App\Models\AuditLog;
use App\Models\Product;
use App\Models\Sale;

/**
 * Ticket AV2 — L'ANNULATION D'UNE VENTE, UN SEUL POINT DE PASSAGE.
 *
 * Extraite de `Livewire\Ventes\HistoriqueVentes::cancelSale()` (le bouton « Annuler » de l'historique) pour que la
 * demande d'annulation d'un poste (`SyncController::pushSales`, vente connue renvoyée au statut `annulee`) fasse
 * exactement la même chose : réintégrer le stock des produits vendus (`AdjustStockAction`, jamais un simple
 * changement de statut) puis passer la vente à `annulee`.
 *
 * ⚠️ IDEMPOTENT : une vente déjà annulée n'est pas rejouée (le stock ne remonte pas deux fois).
 *
 * ⚠️ Ni l'écriture comptable de la vente, ni sa créance, ni l'encaissement ne sont défaits ici — comme au web depuis
 * le ticket 4.4 : seul le stock suit. Le poste reprend ce périmètre à l'identique (doctrine, article 5) ; la
 * contre-passation d'une vente annulée est une question ouverte du client (`docs/PLAN_FINALISATION.md`).
 *
 * @return bool  `true` si la vente vient d'être annulée, `false` si elle l'était déjà
 */
class AnnulerVenteAction
{
    public function execute(Sale $sale): bool
    {
        $sale->loadMissing('lines');

        if ($sale->status === 'annulee') {
            return false;
        }

        foreach ($sale->lines as $line) {
            $product = Product::find($line->product_id);
            if ($product) {
                app(AdjustStockAction::class)->execute($product, (float) $line->qty, 'sale', $sale->id);
            }
        }

        $sale->update(['status' => 'annulee']);

        AuditLog::record('sale.cancelled', 'ventes', null, $sale);

        return true;
    }
}
