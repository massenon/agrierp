<?php

namespace App\Services;

use App\Models\Product;
use App\Models\StockMovement;

/**
 * Ticket 14.46 (Sprint 14) — LE GRAND LIVRE DE STOCK D'ŒUFS, UN SEUL POINT DE
 * VÉRITÉ.
 *
 * La logique SRH / TS / OS / Stock Final avait été construite au ticket 14.13
 * à l'intérieur du composant `FichePondeuses`. Le rapport Synthèse Élevage en
 * avait besoin à son tour (Tableau 3), et sa limite disait alors : « suppose un
 * grand livre de stock d'œufs qui n'existe nulle part dans ce projet ». Il
 * existait — enfermé dans un écran.
 *
 * ⚠️ EXTRAIT PLUTÔT QUE RECOPIÉ. Deux implémentations du même solde d'œufs
 * finissent toujours par diverger, et la ferme lirait alors deux stocks
 * différents selon l'écran ouvert. Les deux corrections durement acquises au
 * ticket 14.13 vivent donc ici, une seule fois :
 *   1. le SRH est reconstruit depuis l'HISTORIQUE réel des mouvements, borné
 *      strictement avant la date consultée — jamais `products.stock_qty`, qui
 *      est le solde de MAINTENANT et afficherait le stock du jour présent sur
 *      la fiche d'un jour passé ;
 *   2. l'OS compte les sorties de VENTE seules (`reference_type = 'sale'`) —
 *      une casse ou un ajustement d'inventaire ne sont pas des ventes.
 *
 * FORMULES, REPRISES TELLES QUELLES DU PROTOTYPE (`rapport-elevage-synth.html`,
 * pied du Tableau 3) :
 *     Total Stock (TS) = (OR − OF) + SRH
 *     Stock Final      = TS − OS
 *
 * ⚠️ LE SOLDE EST TENU AU NIVEAU DU PRODUIT, DONC DE LA FERME ENTIÈRE, jamais
 * par bande : le stock d'œufs est un stock de marchandise, et rien ne distingue
 * dans `stock_movements` l'œuf issu d'une bande de celui issu d'une autre. Deux
 * bandes pondeuses le même jour lisent donc le même SRH. Le dire est la seule
 * option honnête ; répartir au prorata inventerait une traçabilité inexistante.
 */
class EggStockLedgerService
{
    /**
     * ⚠️ 30 œufs par plateau — valeur PROUVÉE par les données du prototype
     * (`rapport-elevage-synth.html` : OS « 14 (420 œufs) », Stock Final « 7
     * plateaux + 8 vrac » pour un TS de 638), jamais une convention supposée.
     */
    public const OEUFS_PAR_PLATEAU = 30;

    private ?Product $produitMemo = null;

    private bool $produitResolu = false;

    /**
     * Le produit qui porte le stock d'œufs. Résolu par son LIBELLÉ, faute d'un
     * indicateur dédié au schéma `products` — convention héritée du ticket
     * 14.13, conservée pour ne pas créer une seconde règle de résolution.
     *
     * 🔴→✅ DÉFAUT LATENT CORRIGÉ AU PASSAGE. La version d'origine cherchait
     * `name LIKE '%œufs%' OR name LIKE '%oeufs%'`. Or le produit réel du
     * catalogue s'appelle « **Œ**ufs de table (plateau) », avec la LIGATURE EN
     * MAJUSCULE : une collation qui ne rapproche pas « Œ » de « œ » ne le
     * trouve pas, et tout le grand livre retombe silencieusement à zéro. Le
     * cas ne se voyait pas sur MySQL (`utf8mb4_unicode_ci` les confond) mais
     * apparaît dès qu'on le teste ailleurs — un solde d'œufs qui vaut zéro
     * sans erreur est exactement le genre de panne qu'on ne remarque pas.
     * La comparaison est donc faite en PHP, sur un libellé normalisé.
     */
    public function eggProduct(): ?Product
    {
        if ($this->produitResolu) {
            return $this->produitMemo;
        }

        $this->produitResolu = true;
        $this->produitMemo = Product::orderBy('name')->get()
            ->first(fn (Product $p) => str_contains($this->normaliser((string) $p->name), 'oeufs'));

        return $this->produitMemo;
    }

    /** Minuscules, ligature « œ » ramenée à « oe ». */
    private function normaliser(string $libelle): string
    {
        return str_replace('œ', 'oe', mb_strtolower($libelle));
    }

    /** Conversion d'un nombre d'œufs en plateaux entiers + vrac. */
    public function enPlateaux(int $oeufs): array
    {
        $oeufs = max(0, $oeufs);

        return [
            'plateaux' => intdiv($oeufs, self::OEUFS_PAR_PLATEAU),
            'vrac' => $oeufs % self::OEUFS_PAR_PLATEAU,
        ];
    }

    /** Solde réel du produit œufs à la veille de la date consultée. */
    public function stockAvant(string $date): float
    {
        $produit = $this->eggProduct();

        if (! $produit) {
            return 0.0;
        }

        $mouvements = StockMovement::where('product_id', $produit->id)
            ->whereDate('movement_date', '<', $date)
            ->selectRaw("SUM(CASE WHEN type = 'sortie' THEN quantity ELSE 0 END) as sorties, SUM(CASE WHEN type <> 'sortie' THEN quantity ELSE 0 END) as entrees")
            ->first();

        return round((float) ($mouvements->entrees ?? 0) - (float) ($mouvements->sorties ?? 0), 2);
    }

    /** Sorties de VENTE du jour, à l'exclusion des casses et ajustements. */
    public function ventesDu(string $date): float
    {
        $produit = $this->eggProduct();

        if (! $produit) {
            return 0.0;
        }

        return round((float) StockMovement::where('product_id', $produit->id)
            ->where('type', 'sortie')
            ->where('reference_type', 'sale')
            ->whereDate('movement_date', $date)
            ->sum('quantity'), 2);
    }

    /**
     * Ligne complète du grand livre pour une journée.
     *
     * @param  int  $commercialisables  œufs récoltés moins cassés, EN ŒUFS
     * @return array{srh: float, ts: float, os: float, final: float, plateaux: int, vrac: int}
     */
    public function ligne(string $date, int $commercialisables): array
    {
        $enPlateaux = $this->enPlateaux($commercialisables);

        $srh = $this->stockAvant($date);
        $ts = $srh + $enPlateaux['plateaux'];
        $os = $this->ventesDu($date);

        return [
            'srh' => $srh,
            'ts' => $ts,
            'os' => $os,
            'final' => $ts - $os,
            'plateaux' => $enPlateaux['plateaux'],
            'vrac' => $enPlateaux['vrac'],
        ];
    }
}
