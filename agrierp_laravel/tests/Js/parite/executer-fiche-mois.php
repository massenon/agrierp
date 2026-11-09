<?php

/**
 * PWA-3 (fiche lapins, É2) — PARITÉ EXÉCUTÉE de `resources/js/hors-ligne/fiche-lapins-ecran.js` (`modeleFiche`) : chaque scénario (bandes, fiches,
 * soins, produits, exercices, jour « aujourd'hui », jour et bande choisis) est écrit dans une base SQLITE EN MÉMOIRE (migrations réelles), puis
 * le VRAI composant `FicheLapins` donne KPI, tableau mensuel, taux, traitements, libellé du mois, bandeau et transferts du jour.
 *
 *   php tests/Js/parite/executer-fiche-mois.php < scenarios.json
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
app()->setLocale('fr');

use App\Livewire\Elevage\FicheLapins;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\VeterinaryRecord;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

$entree = json_decode(stream_get_contents(STDIN), true);
$sortie = [];

foreach ($entree['scenarios'] as $i => $s) {
    DB::beginTransaction();
    try {
        Carbon::setTestNow(Carbon::parse($s['aujourdhui'].' 12:00:00', 'Africa/Porto-Novo'));
        session()->flush();
        $categorie = ProductCategory::create(['label' => 'Parité', 'is_active' => true]);
        foreach ($s['produits'] as $p) {
            $produit = new Product(['sku' => 'S'.$p['id'], 'name' => $p['name'], 'category_id' => $categorie->id, 'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 2, 'stock_qty' => 1, 'is_active' => true]);
            $produit->id = $p['id'];
            $produit->save();
        }
        foreach ($s['exercices'] as $e) {
            FiscalYear::create(['year' => $e['year'], 'start_date' => $e['start_date'], 'end_date' => $e['end_date'], 'status' => $e['status']]);
        }
        $especes = [];
        foreach ($s['lots'] as $l) {
            $especes[$l['species_code']] ??= LivestockSpecies::firstOrCreate(['code' => $l['species_code']], ['label' => ucfirst($l['species_code']), 'is_enabled' => true]);
            $lot = new LivestockLot(['code' => $l['code'], 'species_id' => $especes[$l['species_code']]->id, 'stage' => 'reproduction', 'initial_quantity' => $l['initial_quantity'], 'current_quantity' => $l['current_quantity'], 'created_date' => '2026-01-01', 'status' => $l['status'], 'is_active' => $l['is_active']]);
            $lot->id = $l['id'];
            $lot->save();
        }
        foreach ($s['fiches'] as $f) {
            $fiche = new LivestockDailyEntry;
            $fiche->forceFill($f);
            $fiche->save();
        }
        foreach ($s['soins'] as $r) {
            $soin = new VeterinaryRecord;
            $soin->forceFill($r);
            $soin->save();
        }

        $c = new FicheLapins;
        $c->selectedDate = $s['date'];
        $c->bandeId = $s['bandeId'];
        $kpis = $c->getKpisProperty();
        $mensuel = $c->getMonthlyEntriesProperty();
        $jours = [];
        foreach ($c->getDaysInMonthProperty() as $numero) {
            $jour = $c->debutMoisFiche()->copy()->day($numero)->format('Y-m-d');
            $entry = $mensuel->get($jour);
            $jours[] = [
                'date' => $jour,
                'fiche' => $entry === null ? null : [
                    'taux' => number_format($entry->mortality_rate, 1),
                    'poids_general_g' => $entry->poids_general_g,
                    'effectif_final' => $entry->effectif_final,
                    'effectif_m' => $entry->effectif_m,
                    'mort' => $entry->mort,
                ],
                'traitements' => $c->traitementsDuJour($jour, $entry),
            ];
        }
        $sortie[$i] = [
            'kpis' => $kpis,
            'jours' => $jours,
            'libelleMois' => $c->getLibelleMoisProperty(),
            'estMoisCourant' => $c->getEstMoisCourantProperty(),
            'bandeau' => $c->getBandeauLectureSeuleProperty(),
            'transferts' => $c->getTransfertsDuJourProperty(),
            'bande' => $c->getBandeProperty()?->id,
        ];
    } finally {
        DB::rollBack();
        Carbon::setTestNow();
    }
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION);
