<?php

namespace App\Services;

use App\Actions\RecordPurchaseAction;
use App\Models\AuditLog;
use App\Models\Purchase;
use App\Models\PurchaseOrder;
use Illuminate\Support\Facades\DB;

/**
 * Ticket AC-1 — POINT DE PASSAGE UNIQUE DE LA RÉCEPTION D'UN BON DE COMMANDE.
 *
 * Appelé par `Livewire\Achats\BonsCommande::confirmReceiveOrder` (le web) ET par le push des achats du poste
 * (`SyncController::pushPurchases`, quand l'achat porte `purchase_order_id`) : la réception d'un bon fait la même chose
 * partout — facture d'achat formelle (`RecordPurchaseAction`), stock, dette entière, écriture, bon `recu`, en UNE
 * transaction.
 *
 * ⚠️ Le prix estimé devient le prix réel (aucun autre prix n'est capturé à la réception) ; aucun règlement n'est capturé :
 * la facture est intégralement due (`credit`, règlement nul). Les lignes sont CELLES DU BON, jamais celles qu'un poste
 * enverrait : le bon est le maître.
 *
 * @return Purchase|null l'achat créé, ou `null` si le bon était déjà reçu (rien n'est rejoué).
 */
class ReceptionBonCommandeService
{
    public function recevoir(string $bonId, ?string $purchaseId = null, ?string $purchaseDate = null, ?\DateTimeInterface $instant = null): ?Purchase
    {
        return DB::transaction(function () use ($bonId, $purchaseId, $purchaseDate, $instant) {
            // Verrou + relecture du statut DANS la transaction : un second écran / double clic ne reçoit pas deux fois.
            $bon = PurchaseOrder::with('lines')->lockForUpdate()->findOrFail($bonId);

            if ($bon->status === 'recu' || Purchase::where('purchase_order_id', $bon->id)->exists()) {
                return null;
            }

            $achat = app(RecordPurchaseAction::class)->execute(
                supplierId: $bon->supplier_id,
                lignes: $bon->lines->map(fn ($l) => [
                    'product_id' => $l->product_id,
                    'qty' => $l->qty,
                    'unit_price' => $l->estimated_unit_price,
                ])->all(),
                paymentMode: 'credit',
                treasuryAccountId: '',
                montantRegle: 0.0,
                purchaseId: $purchaseId,
                purchaseDate: $purchaseDate,
                purchaseOrderId: $bon->id,
                instantDuMouvement: $instant,
            );

            $bon->update(['status' => 'recu']);

            AuditLog::record('purchase_order.received', 'achats');

            return $achat;
        });
    }
}
