<?php

/**
 * PWA-3 (délai fournisseur constaté) — PARITÉ EXÉCUTÉE de `delaisFournisseurs` / `seuilCritique` de `fiche-lapins-calculs.js` contre le VRAI
 * `ReleveTerrainService::delaisFournisseurs()` et `regleEnVigueur()` (SQLite en mémoire) : bons de commande reçus de la catégorie « Aliments »,
 * 5 derniers par fournisseur, délai du jour du bon au jour de la réception, règle de terrain validée ou non.
 *
 *   php tests/Js/parite/executer-delais.php < scenarios.json
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
use App\Models\Product;
use App\Models\ProductCategory;
use App\Services\Elevage\ReleveTerrainService;
use Illuminate\Support\Facades\DB;

$entree = json_decode(stream_get_contents(STDIN), true);
$sortie = [];
foreach ($entree['scenarios'] as $i => $s) {
    DB::beginTransaction();
    try {
        $categories = [];
        foreach (['Aliments', 'Médicaments'] as $label) {
            $categories[$label] = ProductCategory::create(['label' => $label, 'is_active' => true]);
        }
        foreach ($s['fournisseurs'] as $f) {
            DB::table('suppliers')->insert(['id' => $f['id'], 'name' => $f['name'], 'is_active' => true, 'created_at' => now(), 'updated_at' => now()]);
        }
        foreach ($s['produits'] as $p) {
            $produit = new Product(['sku' => 'S'.$p['id'], 'name' => 'P'.$p['id'], 'category_id' => $categories[$p['categorie']]->id, 'unit' => 'kg', 'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 2, 'stock_qty' => 1, 'is_active' => true]);
            $produit->id = $p['id'];
            $produit->save();
        }
        foreach ($s['bons'] as $b) {
            DB::table('purchase_orders')->insert(['id' => $b['id'], 'supplier_id' => $b['supplier_id'], 'status' => $b['status'], 'created_at' => $b['created_at'], 'updated_at' => $b['created_at']]);
            foreach ($b['lignes'] as $k => $produitId) {
                DB::table('purchase_order_lines')->insert(['id' => $b['id'].'-l'.$k, 'purchase_order_id' => $b['id'], 'product_id' => $produitId, 'qty' => 1, 'created_at' => $b['created_at'], 'updated_at' => $b['created_at']]);
            }
            if ($b['reception'] !== null) {
                DB::table('purchases')->insert(['id' => $b['id'].'-a', 'supplier_id' => $b['supplier_id'], 'purchase_order_id' => $b['id'], 'payment_mode' => 'especes', 'total' => 1, 'purchase_date' => $b['reception'], 'created_at' => $b['created_at'], 'updated_at' => $b['created_at']]);
            }
        }
        if ($s['releve'] !== null) {
            $r = new FieldSurveyEntry;
            $r->forceFill(['type' => 'delai_regle', 'label' => 'Règle', 'data' => $s['releve']['data'], 'status' => $s['releve']['status'], 'is_active' => true]);
            $r->id = $s['releve']['id'];
            $r->save();
        }
        $regle = ReleveTerrainService::regleEnVigueur();
        $sortie[$i] = [
            'delais' => array_map(fn ($d) => ['supplier_id' => $d['supplier_id'], 'nb' => $d['nb'], 'critique_propose' => $d['critique_propose'], 'delais' => array_column($d['bons'], 'delai_jours')], ReleveTerrainService::delaisFournisseurs()),
            'critique' => $regle['critique'], 'source' => $regle['source'],
        ];
    } finally {
        DB::rollBack();
    }
}
echo json_encode($sortie, JSON_UNESCAPED_UNICODE);
