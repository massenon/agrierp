<?php

namespace App\Services;

use App\Models\CreditNote;
use App\Models\SaleLine;
use Illuminate\Support\Collection;

/**
 * Ticket 15.12 — REVENU PAR BANDE : UN SEUL CALCUL, DEUX SURFACES.
 *
 * Extrait de `Livewire\Elevage\BilanTechnicoEconomique` (ticket 14.44) pour que
 * le tirage du poste (`/api/sync/pull`, bloc `lot_revenues`) et la page web
 * servent EXACTEMENT le même chiffre. Le poste ne reçoit des ventes serveur que
 * leur en-tête, sans lignes (`SyncController`, ticket 14.80) : il ne peut donc
 * pas recalculer un revenu par bande, et le recalculer autrement ici ferait un
 * second chiffre qui finirait par diverger.
 *
 * ⚠️ RÈGLES, INCHANGÉES DEPUIS 14.44 :
 *  - seules les ventes VALIDÉES comptent (une vente annulée n'est pas un revenu) ;
 *  - le montant d'une ligne est `manual_total_amount` quand il est renseigné et
 *    non nul, sinon quantité × prix unitaire ;
 *  - les AVOIRS TRAITÉS portant sur une vente de la bande sont déduits, produit
 *    par produit : un retour marchandise n'est pas un revenu de cette bande.
 */
class LotRevenueService
{
    /**
     * Revenus d'UNE bande, une ligne par produit effectivement vendu.
     *
     * @return array<int, array{product_id: string, label: string, montant: float, reel: bool}>
     */
    public function forLot(string $lotId): array
    {
        return $this->forLots([$lotId])[$lotId] ?? [];
    }

    /**
     * @param  array<int, string>|null  $lotIds  `null` = toutes les bandes
     * @return array<string, array<int, array{product_id: string, label: string, montant: float, reel: bool}>>
     */
    public function forLots(?array $lotIds = null): array
    {
        $lignes = SaleLine::query()
            ->join('sales', 'sales.id', '=', 'sale_lines.sale_id')
            ->join('products', 'products.id', '=', 'sale_lines.product_id')
            ->whereNotNull('sale_lines.lot_id')
            ->when($lotIds !== null, fn ($q) => $q->whereIn('sale_lines.lot_id', $lotIds))
            ->where('sales.status', 'validee')
            ->groupBy('sale_lines.lot_id', 'products.id', 'products.name')
            ->selectRaw('sale_lines.lot_id as lot_id, products.id as product_id, products.name as nom, SUM(COALESCE(NULLIF(sale_lines.manual_total_amount, 0), sale_lines.qty * sale_lines.unit_price)) as montant')
            ->orderBy('products.name')
            ->get();

        $avoirs = $this->avoirsTraites($lotIds);

        $parBande = [];

        foreach ($lignes as $l) {
            $parBande[$l->lot_id][] = [
                'product_id' => $l->product_id,
                'label' => 'Ventes — '.$l->nom,
                'montant' => round((float) $l->montant - (float) ($avoirs[$l->lot_id.'|'.$l->product_id] ?? 0), 2),
                'reel' => true,
            ];
        }

        return $parBande;
    }

    /**
     * Avoirs traités, par couple bande|produit.
     *
     * ⚠️ UN AVOIR PORTE SUR UN COUPLE vente + produit : il est rattaché à la
     * bande par la ligne de vente correspondante. Joindre sur la vente seule
     * déduirait l'avoir de TOUTES les bandes de cette vente.
     *
     * @return Collection<string, float>
     */
    private function avoirsTraites(?array $lotIds): Collection
    {
        return CreditNote::query()
            ->join('sale_lines', function ($j) {
                $j->on('sale_lines.sale_id', '=', 'credit_notes.sale_id')
                    ->on('sale_lines.product_id', '=', 'credit_notes.product_id');
            })
            ->whereNotNull('sale_lines.lot_id')
            ->when($lotIds !== null, fn ($q) => $q->whereIn('sale_lines.lot_id', $lotIds))
            ->where('credit_notes.status', 'traite')
            ->groupBy('sale_lines.lot_id', 'credit_notes.product_id')
            ->selectRaw('sale_lines.lot_id as lot_id, credit_notes.product_id as product_id, SUM(credit_notes.amount) as montant')
            ->get()
            ->mapWithKeys(fn ($a) => [$a->lot_id.'|'.$a->product_id => (float) $a->montant]);
    }
}
