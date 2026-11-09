<?php

/**
 * PWA-1b / PWA-3 — PARITÉ EXÉCUTÉE de `resources/js/hors-ligne/chaine-effectif.js` : chaque scénario (une bande, ses fiches, UNE vente)
 * est rejoué sur le VRAI `RecordSaleOnFicheElevageAction::execute` (base SQLITE EN MÉMOIRE, migrations réelles) : refus éventuel,
 * puis fiches et quantité de la bande obtenues. Aucune donnée n'est conservée (une transaction annulée par scénario).
 *
 *   php tests/Js/parite/executer-chaine.php < scenarios.json
 */

putenv('APP_ENV=testing');
putenv('DB_CONNECTION=sqlite');
putenv('DB_DATABASE=:memory:');
$_ENV['APP_ENV'] = 'testing';
$racine = dirname(__DIR__, 3);
require $racine.'/vendor/autoload.php';
$app = require $racine.'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
if (config('database.default') !== 'sqlite' || config('database.connections.sqlite.database') !== ':memory:') {
    fwrite(STDERR, "Refus : la base n'est pas une base SQLite en mémoire.");
    exit(3);
}
Illuminate\Support\Facades\Artisan::call('migrate', ['--force' => true]);

use App\Actions\RecordSaleOnFicheElevageAction;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

$entree = json_decode(stream_get_contents(STDIN), true);
$categorie = ProductCategory::create(['label' => 'Parité', 'is_active' => true]);
$produits = [];
foreach (['Poulet fermier', 'Lapin vivant', 'Œufs'] as $nom) {
    $produits[$nom] = Product::create(['sku' => 'P'.count($produits), 'name' => $nom, 'category_id' => $categorie->id, 'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 2, 'stock_qty' => 100, 'is_active' => true]);
}
$especes = [];
$COLONNES = ['achat', 'ne', 'mort', 'vente', 'don', 'effectif_final', 'mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune',
    'passage_sevre_jeune', 'vente_repro', 'vente_sevre', 'vente_jeune', 'mort_4', 'don_4', 'vente_4', 'passage_4_sevre', 'passage_jeune_repro',
    'cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune', 'cat_eff_4', 'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune', 'cat_depart_4'];
$TRANSFERTS = ['transfert_entree', 'transfert_sortie', 'transfert_entree_repro', 'transfert_entree_sevre', 'transfert_entree_jeune', 'transfert_sortie_repro', 'transfert_sortie_sevre', 'transfert_sortie_jeune', 'transfert_entree_4', 'transfert_sortie_4'];

$sortie = [];
foreach ($entree['scenarios'] as $i => $s) {
    DB::beginTransaction();
    try {
        $code = $s['lot']['species_code'];
        $espece = LivestockSpecies::create(['code' => $code, 'label' => ucfirst($code), 'is_enabled' => true]);
        $lot = new LivestockLot(['code' => 'B'.$i, 'species_id' => $espece->id, 'stage' => $s['lot']['stage'], 'initial_quantity' => $s['lot']['initial_quantity'], 'current_quantity' => $s['lot']['current_quantity'], 'created_date' => '2026-01-01', 'status' => 'actif', 'is_active' => true]);
        $lot->id = (string) Str::uuid();
        $lot->save();

        foreach ($s['fiches'] as $f) {
            $fiche = new LivestockDailyEntry(array_intersect_key($f, array_flip(array_merge($COLONNES, ['entry_date']))) + ['lot_id' => $lot->id]);
            $fiche->id = (string) Str::uuid();
            foreach ($TRANSFERTS as $t) {
                if (isset($f[$t])) {
                    $fiche->{$t} = $f[$t];
                }
            }
            $fiche->save();
        }

        // PWA-3 — lecture de la chaîne AVANT la vente : état d'un jour (`etatPourJour`) et refus d'une fiche proposée (`refusDuPassage`).
        $service = app(\App\Services\EffectifParCategorieService::class);
        $lotFrais = LivestockLot::with('species')->find($lot->id);
        $res = ['refus' => null, 'etat' => $service->etatPourJour($lotFrais, $s['etat_jour'])];
        $p = $s['proposee'];
        $proposee = new LivestockDailyEntry(array_intersect_key($p, array_flip(array_merge($COLONNES, ['entry_date']))) + ['lot_id' => $lot->id]);
        $proposee->id = 'proposee';
        $res['passage'] = $service->refusDuPassage($lotFrais, $proposee);
        $ligne = ['lot_id' => $lot->id, 'qty' => $s['vente']['qty'], 'product_id' => $produits[$s['vente']['nom_produit']]->id];
        if ($s['vente']['categorie_effectif'] !== null) {
            $ligne['categorie_effectif'] = $s['vente']['categorie_effectif'];
        }
        try {
            app(RecordSaleOnFicheElevageAction::class)->execute([$ligne], $s['vente']['jour']);
        } catch (ValidationException $e) {
            $res['refus'] = $e->errors()['lines'][0];
        }

        $res['fiches'] = LivestockDailyEntry::where('lot_id', $lot->id)->orderBy('entry_date')->get()->map(function ($f) use ($COLONNES) {
            $o = ['entry_date' => $f->entry_date->format('Y-m-d')];
            foreach ($COLONNES as $c) {
                $o[$c] = $f->{$c} === null ? null : (int) $f->{$c};
            }

            return $o;
        })->all();
        $res['current_quantity'] = (int) LivestockLot::find($lot->id)->current_quantity;
        $sortie[$i] = $res;
    } finally {
        DB::rollBack();
    }
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE);
