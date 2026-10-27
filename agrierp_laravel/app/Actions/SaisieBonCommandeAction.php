<?php

namespace App\Actions;

use App\Models\AuditLog;
use App\Models\PurchaseOrder;
use App\Models\PurchaseOrderLine;
use Illuminate\Support\Facades\DB;

/**
 * Ticket AC-1 — POINT DE PASSAGE UNIQUE DE LA SAISIE D'UN BON DE COMMANDE.
 *
 * Appelé par `Livewire\Achats\BonsCommande::generateBc` (le web) ET par `SyncController::pushPurchaseOrders` (le poste) : un
 * bon saisi hors ligne se crée comme un bon saisi au web — même statut `envoye`, mêmes lignes, même trace d'audit.
 *
 * ⚠️ IDEMPOTENCE : l'identifiant du bon (et ceux de ses lignes) vient du poste ; un bon déjà reçu est rendu tel quel, sans
 * rien recréer (un accusé perdu en route ne doit pas faire deux bons). L'identifiant se pose HORS de `create()` : `id`
 * n'est pas dans `$fillable`.
 */
class SaisieBonCommandeAction
{
    /**
     * @param  array<int, array{product_id: string, qty: float|int, estimated_unit_price: float|int, id?: string|null}>  $lignes
     */
    public function execute(string $supplierId, ?string $expectedDeliveryDate, array $lignes, ?string $bonId = null): PurchaseOrder
    {
        if ($bonId !== null && ($existant = PurchaseOrder::find($bonId)) !== null) {
            return $existant;
        }

        return DB::transaction(function () use ($supplierId, $expectedDeliveryDate, $lignes, $bonId) {
            $bon = new PurchaseOrder();
            if ($bonId !== null) {
                $bon->id = $bonId;
            }
            $bon->fill([
                'supplier_id' => $supplierId,
                'expected_delivery_date' => $expectedDeliveryDate ?: null,
                'status' => 'envoye',
            ]);
            $bon->save();

            foreach ($lignes as $ligne) {
                $nouvelle = new PurchaseOrderLine();
                if (! empty($ligne['id'])) {
                    $nouvelle->id = $ligne['id'];
                }
                $nouvelle->fill([
                    'purchase_order_id' => $bon->id,
                    'product_id' => $ligne['product_id'],
                    'qty' => $ligne['qty'],
                    'estimated_unit_price' => $ligne['estimated_unit_price'],
                ]);
                $nouvelle->save();
            }

            AuditLog::record('purchase_order.created', 'achats');

            return $bon;
        });
    }
}
