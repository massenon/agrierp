<?php

namespace App\Services;

use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\Product;

/**
 * Autonomie alimentaire : combien de jours le stock de provende d'une filière couvre-t-il ?
 *
 * Un seul calcul pour les fiches Lapins et Porcs (consommation du jour affiché) et pour le tiroir de
 * Gestion des Bandes (consommation de la filière). Il était recopié dans chaque fiche.
 *
 * ⚠️ L'AUTONOMIE INFORME, ELLE NE BLOQUE JAMAIS : une fiche journalière s'enregistre stock vide ou non.
 * L'éleveur nourrit ses animaux qu'il y ait de la provende en catalogue ou non ; refuser la fiche
 * ferait perdre la trace de la journée, pas la rupture.
 */
class AutonomieAlimentaireService
{
    /** En dessous de ce nombre de jours, l'autonomie est critique (même seuil que RaiseFeedAutonomyAlertAction). */
    public const SEUIL_CRITIQUE_JOURS = 3.0;

    /** Produit de provende suivi en stock pour une filière (repéré par l'espèce et « provende » / « aliment » dans le nom). */
    public function produitProvende(string $speciesCode): ?Product
    {
        return Product::whereHas('species', fn ($q) => $q->where('code', $speciesCode))
            ->where(fn ($q) => $q->where('name', 'like', '%provende%')->orWhere('name', 'like', '%aliment%'))
            ->first();
    }

    /**
     * @param  float|null  $consommationKgJour  null = consommation inconnue (jamais prise pour 0)
     * @return array{available: bool, inconnu?: bool, product?: Product, stock_kg?: float, autonomie_jours?: ?float, critique?: bool, rupture?: bool}
     */
    public function evaluer(?Product $produit, ?float $consommationKgJour): array
    {
        if (! $produit) {
            return ['available' => false];
        }

        $stockKg = $produit->stockEnKg();
        $rupture = $stockKg <= 0;

        if ($consommationKgJour === null) {
            return ['available' => true, 'inconnu' => true, 'product' => $produit, 'stock_kg' => $stockKg,
                'autonomie_jours' => null, 'critique' => $rupture, 'rupture' => $rupture];
        }

        $autonomieJours = $consommationKgJour > 0 ? round($stockKg / $consommationKgJour, 1) : 99;

        return [
            'available' => true,
            'product' => $produit,
            'stock_kg' => $stockKg,
            'autonomie_jours' => $autonomieJours,
            'critique' => $rupture || $autonomieJours <= self::SEUIL_CRITIQUE_JOURS,
            'rupture' => $rupture,
        ];
    }

    /**
     * Autonomie d'une FILIÈRE : stock de sa provende ÷ provende servie à ses bandes vivantes, chacune prise sur sa
     * DERNIÈRE fiche (`feed_qty_kg`, calculée automatiquement par les fiches Lapins et Porcs). Une bande vivante
     * dont la dernière fiche n'a pas de provende connue rend la consommation inconnue, jamais 0.
     */
    public function pourEspece(string $speciesCode): array
    {
        $bandes = LivestockLot::vivantes()->whereHas('species', fn ($q) => $q->where('code', $speciesCode))->pluck('id');

        $consommation = 0.0;
        foreach ($bandes as $bandeId) {
            $derniere = LivestockDailyEntry::where('lot_id', $bandeId)->orderByDesc('entry_date')->first();
            if ($derniere === null) {
                continue;               // bande sans fiche : rien de servi à ce jour
            }
            if ($derniere->feed_qty_kg === null) {
                $consommation = null;
                break;
            }
            $consommation += (float) $derniere->feed_qty_kg;
        }

        return $this->evaluer($this->produitProvende($speciesCode), $consommation);
    }
}
