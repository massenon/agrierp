<?php

namespace App\Http\Controllers\Api;

use App\Models\Product;
use App\Models\Receivable;
use App\Models\Sale;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * PWA-4 — Snapshot hors ligne (11/11/2026)
 *
 * Fournit un instantané JSON des trois modules de consultation hors ligne :
 *   - stock      : produits actifs (view-stocks)
 *   - creances   : créances actives, solde > 0 (view-ventes)
 *   - ventes     : 30 dernières ventes normalisées (view-ventes)
 *
 * Appelé depuis le JavaScript du navigateur (cookie de session Sanctum) au
 * moment de la connexion et périodiquement, puis stocké en IndexedDB sous
 * la clé `offline_snapshot`. La réponse JSON n'est jamais mise en cache par
 * le service worker (règle 3 de sw.js : jamais du JSON).
 *
 * Droits : route protégée par `auth:sanctum` + `CompteActif`.
 * Les trois blocs de données sont gardés par leurs permissions propres ;
 * les blocs auxquels le compte n'a pas accès sont retournés vides ([]).
 */
class OfflineSnapshotController
{
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        // --- Stock : produits actifs avec quantité et seuil d'alerte ---
        $stock = [];
        if ($user->can('view-stocks')) {
            $stock = Product::where('is_active', true)
                ->orderBy('name')
                ->get(['id', 'name', 'stock_qty', 'alert_threshold', 'unit'])
                ->map(fn (Product $p) => [
                    'id'              => $p->id,
                    'name'            => $p->name,
                    'stock_qty'       => (float) $p->stock_qty,
                    'alert_threshold' => (float) $p->alert_threshold,
                    'unit'            => $p->unit,
                ])
                ->values()
                ->all();
        }

        // --- Créances : créances actives dont le solde dû est positif ---
        $creances = [];
        if ($user->can('view-ventes')) {
            $creances = Receivable::where('status', '!=', 'soldee')
                ->whereColumn('amount_paid', '<', 'amount')
                ->with('customer:id,name')
                ->orderBy('due_date')
                ->get(['id', 'customer_id', 'amount', 'amount_paid', 'due_date'])
                ->map(fn (Receivable $r) => [
                    'id'            => $r->id,
                    'customer_name' => $r->customer?->name ?? '—',
                    'amount_due'    => round((float) $r->amount - (float) $r->amount_paid, 2),
                    'due_date'      => $r->due_date?->toDateString(),
                ])
                ->values()
                ->all();
        }

        // --- Ventes récentes : 30 dernières ventes non annulées ---
        $ventesRecentes = [];
        if ($user->can('view-ventes')) {
            $ventesRecentes = Sale::nonAnnulees()
                ->orderByRaw(Sale::DATE_EFFECTIVE_SQL . ' DESC')
                ->limit(30)
                ->get(['id', 'sold_at', 'created_at', 'total', 'payment_mode'])
                ->map(fn (Sale $s) => [
                    'id'           => $s->id,
                    'sold_at'      => $s->dateEffective?->toIso8601String(),
                    'total'        => (float) $s->total,
                    'payment_mode' => $s->payment_mode,
                ])
                ->values()
                ->all();
        }

        return response()->json([
            'stock'          => $stock,
            'creances'       => $creances,
            'ventes_recentes' => $ventesRecentes,
            'cached_at'      => now()->toIso8601String(),
        ]);
    }
}
