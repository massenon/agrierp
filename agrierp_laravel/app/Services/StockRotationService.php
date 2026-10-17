<?php

namespace App\Services;

use App\Models\Product;
use App\Models\StockMovement;
use Carbon\CarbonImmutable;

/**
 * Ticket 14.47 (Sprint 14) — ROTATION DU STOCK.
 *
 * La carte KPI de Gestion des Stocks affichait « — / Méthodologie COGS —
 * Sprint 10/12 ». Ce qui manquait n'était pas une décision du client mais une
 * convention de valorisation : « à quel coût sort une marchandise ? ». Le
 * ticket 14.41 l'a tranchée pour l'écart d'inventaire — au **PMP** — et la même
 * convention vaut ici, sans quoi le projet en aurait deux.
 *
 * FORMULE, standard comptable et non règle propre à la ferme :
 *     Rotation = Coût des marchandises vendues (période) ÷ Stock moyen (période)
 *     Stock moyen = (valeur au début + valeur à la fin) ÷ 2
 *
 * Le prototype affiche « 3.5 fois/mois » : la période retenue est donc le MOIS,
 * comme l'unité affichée l'impose.
 *
 * ⚠️ LE COGS NE COMPTE QUE LES SORTIES DE VENTE. Une casse, un don, un écart
 * d'inventaire font baisser le stock sans être des marchandises VENDUES. Les
 * inclure gonflerait la rotation et ferait passer une exploitation qui perd sa
 * marchandise pour une exploitation qui l'écoule vite — exactement l'inverse de
 * ce que l'indicateur doit signaler.
 *
 * ⚠️ STOCK MOYEN NUL ⇒ AUCUNE ROTATION, jamais l'infini ni zéro. Diviser par
 * zéro n'a pas de sens, et afficher « 0 » laisserait croire à un stock dormant
 * alors qu'il n'y a simplement rien à faire tourner.
 *
 * ⚠️ LES PRODUITS SANS PMP CONNU SONT EXCLUS DES DEUX TERMES, et comptés. Un
 * sujet né à la ferme n'a aucun historique d'achat : le compter zéro au
 * numérateur ET au dénominateur biaiserait le ratio dans les deux sens à la
 * fois. Mieux vaut un ratio calculé sur le périmètre valorisable, et dire
 * combien de produits en sont sortis.
 *
 * ⚠️⚠️ CE QUE LA MESURE SUR LES DONNÉES RÉELLES A RÉVÉLÉ, ET QUI CHANGE LA
 * LECTURE DE CE KPI. Sur cette exploitation, les 8 produits disposant d'un PMP
 * sont les INTRANTS ACHETÉS (provendes, poussins d'un jour, un antibiotique,
 * une cage) ; les 19 sans PMP sont exactement ce que la ferme VEND — poulets,
 * œufs, lapins, porcs, maraîchage — parce qu'elle les PRODUIT au lieu de les
 * acheter. Le périmètre valorisable et le périmètre vendu se recouvrent donc à
 * peine : la rotation mesurée vaut 0,04 fois/mois là où le prototype illustre
 * 3,5. Ce n'est pas une erreur de calcul, c'est le profil de l'exploitation.
 *
 * La carte expose pour cette raison le TAUX DE COUVERTURE (part des sorties de
 * vente du mois portant un coût connu) à côté du ratio : un ratio partiel dont
 * le périmètre est affiché reste une information ; le même ratio affiché nu
 * serait un contresens. Valoriser le stock PRODUIT au coût de production
 * lèverait la limite, mais aucune convention de ce type n'est définie par le
 * CDC ni par le prototype — ARBITRAGE CLIENT, jamais une règle inventée ici.
 */
class StockRotationService
{
    /**
     * @return array{rotation: float|null, cogs: float, stock_moyen: float, produits_sans_pmp: int, couverture: float|null}
     */
    public function pourLeMois(?string $mois = null): array
    {
        $debut = $mois ? CarbonImmutable::parse($mois.'-01') : CarbonImmutable::now()->startOfMonth();
        $fin = $debut->endOfMonth();

        $pmp = [];
        $sansPmp = 0;

        foreach (Product::where('is_active', true)->orderBy('sku')->get() as $produit) {
            $valeur = $produit->computePmp();

            if ($valeur === null || $valeur <= 0) {
                $sansPmp++;

                continue;
            }

            $pmp[$produit->id] = $valeur;
        }

        if ($pmp === []) {
            return ['rotation' => null, 'cogs' => 0.0, 'stock_moyen' => 0.0, 'produits_sans_pmp' => $sansPmp, 'couverture' => null];
        }

        $cogs = $this->coutDesVentes(array_keys($pmp), $pmp, $debut->format('Y-m-d'), $fin->format('Y-m-d'));

        $valeurDebut = $this->valeurStockAu($pmp, $debut->subDay()->format('Y-m-d'));
        $valeurFin = $this->valeurStockAu($pmp, $fin->format('Y-m-d'));
        $stockMoyen = round(($valeurDebut + $valeurFin) / 2, 2);

        return [
            'rotation' => $stockMoyen > 0 ? round($cogs / $stockMoyen, 2) : null,
            'cogs' => $cogs,
            'stock_moyen' => $stockMoyen,
            'produits_sans_pmp' => $sansPmp,
            'couverture' => $this->couvertureDesVentes(array_keys($pmp), $debut->format('Y-m-d'), $fin->format('Y-m-d')),
        ];
    }

    /**
     * Part des sorties de vente du mois portant un coût connu — ce que le
     * ratio couvre réellement. `null` s'il n'y a eu aucune vente : une
     * couverture de 0 % et une absence de vente ne se disent pas pareil.
     */
    private function couvertureDesVentes(array $produitIds, string $debut, string $fin): ?float
    {
        $base = StockMovement::where('type', 'sortie')
            ->where('reference_type', 'sale')
            ->whereDate('movement_date', '>=', $debut)
            ->whereDate('movement_date', '<=', $fin);

        $total = (clone $base)->count();

        if ($total === 0) {
            return null;
        }

        return round(100 * (clone $base)->whereIn('product_id', $produitIds)->count() / $total, 1);
    }

    /** Coût, au PMP, des marchandises réellement VENDUES sur la période. */
    private function coutDesVentes(array $produitIds, array $pmp, string $debut, string $fin): float
    {
        $sorties = StockMovement::whereIn('product_id', $produitIds)
            ->where('type', 'sortie')
            ->where('reference_type', 'sale')
            ->whereDate('movement_date', '>=', $debut)
            ->whereDate('movement_date', '<=', $fin)
            ->groupBy('product_id')
            ->selectRaw('product_id, SUM(quantity) as quantite')
            ->pluck('quantite', 'product_id');

        $total = 0.0;

        foreach ($sorties as $produitId => $quantite) {
            $total += (float) $quantite * ($pmp[$produitId] ?? 0);
        }

        return round($total, 2);
    }

    /**
     * Valeur du stock à une date, reconstruite depuis l'historique — jamais
     * `products.stock_qty`, qui est le solde de MAINTENANT.
     *
     * ⚠️ Une quantité négative est valorisée ZÉRO, jamais en déduction : un
     * actif ne peut pas être négatif (même règle qu'au ticket 14.30).
     */
    private function valeurStockAu(array $pmp, string $date): float
    {
        $soldes = StockMovement::whereIn('product_id', array_keys($pmp))
            ->whereDate('movement_date', '<=', $date)
            ->groupBy('product_id')
            ->selectRaw("product_id, SUM(CASE WHEN type = 'sortie' THEN -quantity ELSE quantity END) as solde")
            ->pluck('solde', 'product_id');

        $total = 0.0;

        foreach ($soldes as $produitId => $solde) {
            $total += max(0.0, (float) $solde) * ($pmp[$produitId] ?? 0);
        }

        return round($total, 2);
    }
}
