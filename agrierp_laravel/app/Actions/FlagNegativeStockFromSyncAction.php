<?php

namespace App\Actions;

use App\Models\AuditLog;
use App\Models\Notification;
use App\Models\Product;
use App\Models\Sale;

/**
 * Ticket H14 — VENTE REÇUE D'UN POSTE QUI REND UN STOCK NÉGATIF : ACCEPTÉE ET SIGNALÉE (décision D-SYNC-4 du client,
 * 19/10/2026).
 *
 * 🔴 Avant : le serveur acceptait la vente et décrémentait le stock sans plancher (`AdjustStockAction`), EN SILENCE.
 * Un poste resté hors ligne vend sur son stock local, qui ignore les ventes faites ailleurs entre-temps : le stock du
 * serveur pouvait passer sous zéro sans que personne le sache.
 *
 * ⚠️ LA VENTE N'EST PAS REFUSÉE : elle a eu lieu, l'argent est encaissé. La refuser casserait la caisse hors ligne et
 * retirerait une recette des livres. L'administrateur est prévenu pour régulariser (inventaire, ajustement).
 */
class FlagNegativeStockFromSyncAction
{
    /** @return array<int, string> noms des produits passés sous zéro */
    public function execute(Sale $vente): array
    {
        $ids = $vente->lines->pluck('product_id')->filter()->unique();
        $negatifs = Product::whereIn('id', $ids)->where('stock_qty', '<', 0)->get();

        foreach ($negatifs as $produit) {
            Notification::create([
                'target_role' => 'admin',
                'type' => 'stock_low',
                'severity' => 'critique',
                'title' => "Stock négatif après synchronisation — {$produit->name}",
                'message' => "Une vente reçue d'un poste (vente {$vente->id}) a fait passer le stock de « {$produit->name} » "
                    ."à {$produit->stock_qty} {$produit->unit}. La vente est enregistrée : elle a eu lieu. Vérifiez le stock "
                    .'réel et régularisez par un ajustement d\'inventaire.',
                'icon' => 'inventory_2',
                'is_read' => false,
            ]);
        }

        if ($negatifs->isNotEmpty()) {
            AuditLog::record('sale.negative_stock_received', 'ventes');
        }

        return $negatifs->pluck('name')->all();
    }
}
