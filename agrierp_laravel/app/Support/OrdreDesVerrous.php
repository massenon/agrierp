<?php

namespace App\Support;

use App\Models\LivestockLot;
use App\Models\Product;
use App\Services\EggStockLedgerService;
use Illuminate\Support\Facades\DB;

/**
 * Ticket U14 — ORDRE UNIQUE D'ACQUISITION DES VERROUS « STOCK » ET « FICHE ».
 *
 * 🔴 LE RISQUE CORRIGÉ. La caisse du web verrouillait le STOCK puis la FICHE (`AdjustStockAction` décrémente la ligne
 * `products`, puis `RecordSaleOnFicheElevageAction` écrit la fiche du jour) ; l'envoi d'un poste verrouillait la FICHE
 * puis le STOCK (`pushDailyEntries` écrit les fiches et leur production `SyncLotProductionStockAction`, puis les ventes
 * décrémentent le stock) ; les fiches Porcs et Lapins, la Transformation, la FICHE puis le STOCK. Deux transactions
 * qui prennent les mêmes lignes dans l'ordre inverse s'attendent l'une l'autre : MariaDB en tue une (1213), rejouée par
 * `TransactionRejouable` — le travail est refait, la caisse attend, et au troisième échec l'envoi part en 500.
 *
 * ✅ LA RÈGLE, partout où une transaction touche le stock ET une fiche (envoi des postes, caisse du web, cinq fiches,
 * Transformation) : D'ABORD les lignes `products` qu'elle mouvementera, PAR IDENTIFIANT CROISSANT ([stock]), ENSUITE
 * les fiches et les bandes. Deux transactions qui veulent un même produit se mettent en file sur lui AVANT de toucher la
 * moindre fiche : celle qui attend ne tient encore aucun verrou de fiche, l'interblocage croisé ne peut plus se former.
 * Le tri par identifiant supprime aussi l'interblocage entre deux paniers qui contiennent les mêmes produits dans un
 * ordre différent.
 *
 * ⚠️ HORS TRANSACTION, RIEN N'EST VERROUILLÉ (un verrou de ligne vit le temps de sa transaction) : [stock] ne fait rien.
 * Sur SQLite (suite Feature) `lockForUpdate` n'existe pas — la requête s'exécute sans `FOR UPDATE` : la preuve de l'ordre
 * est faite sur le journal des requêtes (`OrdreDesVerrousTest`) et, sous MariaDB, par l'essai à plusieurs postes.
 */
final class OrdreDesVerrous
{
    /**
     * Verrouille les produits [$ids] (identifiants absents de la base ignorés), par identifiant croissant.
     *
     * @param  iterable<mixed>  $ids
     */
    public static function stock(iterable $ids): void
    {
        $ids = collect($ids)->filter(fn ($id) => is_string($id) && $id !== '')->unique()->sort()->values()->all();
        if ($ids === [] || DB::transactionLevel() === 0) {
            return;
        }

        Product::query()->whereIn('id', $ids)->orderBy('id')->lockForUpdate()->pluck('id');
    }

    /**
     * Produits qu'une fiche de ces bandes peut mouvementer : le produit rattaché à la bande (naissances, morts et dons,
     * `SyncLotProductionStockAction`, 15.56) et, pour une bande de pondeuses, les œufs de table
     * (`RecordEggProductionStockAction`).
     *
     * @param  iterable<mixed>  $lotIds
     * @return array<int, string>
     */
    public static function produitsDesFiches(iterable $lotIds): array
    {
        $lotIds = collect($lotIds)->filter(fn ($id) => is_string($id) && $id !== '')->unique()->values()->all();
        if ($lotIds === []) {
            return [];
        }

        $bandes = LivestockLot::with('species')->whereIn('id', $lotIds)->get(['id', 'product_id', 'stage', 'species_id']);
        $ids = $bandes->pluck('product_id')->filter()->values()->all();

        if ($bandes->contains(fn (LivestockLot $b) => $b->stage === 'ponte' && $b->species?->code === 'aviculture')) {
            $oeufs = app(EggStockLedgerService::class)->eggProduct();
            if ($oeufs !== null) {
                $ids[] = $oeufs->id;
            }
        }

        return $ids;
    }
}
