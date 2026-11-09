<?php

/**
 * PWA-3 (fiche lapins, É5) — PARITÉ EXÉCUTÉE de `fiche-lapins-calculs.js` (produit de provende, stock en kg, seuil critique, autonomie) contre
 * le VRAI `AutonomieAlimentaireService` (SQLite en mémoire) : chaque scénario porte produits, types de provende, relevé de règle et consommation.
 *
 *   php tests/Js/parite/executer-autonomie.php < scenarios.json
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

use App\Models\FieldSurveyEntry;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Services\AutonomieAlimentaireService;
use Illuminate\Support\Facades\DB;

$entree = json_decode(stream_get_contents(STDIN), true);
$sortie = [];
foreach ($entree['scenarios'] as $i => $s) {
    DB::beginTransaction();
    try {
        $especes = [];
        foreach (['cuniculture', 'porciculture'] as $code) {
            $especes[$code] = LivestockSpecies::firstOrCreate(['code' => $code], ['label' => ucfirst($code), 'is_enabled' => true]);
        }
        $categorie = ProductCategory::create(['label' => 'Parité', 'is_active' => true]);
        foreach ($s['produits'] as $p) {
            $produit = new Product(['sku' => 'S'.$p['id'], 'name' => $p['name'], 'category_id' => $categorie->id, 'unit' => $p['unit'], 'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 2, 'stock_qty' => $p['stock_qty'], 'is_active' => true]);
            $produit->id = $p['id'];
            $produit->species_id = $p['espece'] === null ? null : $especes[$p['espece']]->id;
            $produit->save();
        }
        foreach ($s['feed_types'] as $f) {
            DB::table('feed_types')->insert(['id' => $f['id'], 'name' => 'T', 'standard_bag_weight_kg' => $f['standard_bag_weight_kg'], 'price_per_kg' => 1, 'is_active' => true, 'created_at' => now(), 'updated_at' => now()]);
        }
        if ($s['releve'] !== null) {
            $r = new FieldSurveyEntry;
            $r->forceFill(['type' => 'delai_regle', 'label' => 'Règle', 'data' => $s['releve']['data'], 'status' => $s['releve']['status'], 'is_active' => true]);
            $r->id = $s['releve']['id'];
            $r->save();
        }
        $service = app(AutonomieAlimentaireService::class);
        $produit = $service->produitProvende('cuniculture');
        $a = $service->evaluer($produit, $s['consommation']);
        $sortie[$i] = ['available' => $a['available'], 'product' => $produit?->id, 'stock_kg' => $a['stock_kg'] ?? null, 'autonomie_jours' => $a['autonomie_jours'] ?? null,
            'critique' => $a['critique'] ?? null, 'rupture' => $a['rupture'] ?? null, 'inconnu' => $a['inconnu'] ?? false];
    } finally {
        DB::rollBack();
    }
}
echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION);
