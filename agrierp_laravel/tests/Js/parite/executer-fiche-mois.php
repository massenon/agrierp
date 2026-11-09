<?php

/**
 * PWA-3 (fiche lapins, É2) — PARITÉ EXÉCUTÉE de `resources/js/hors-ligne/fiche-lapins-ecran.js` (`modeleFiche`) : chaque scénario (bandes, fiches,
 * soins, produits, exercices, jour « aujourd'hui », jour et bande choisis) est écrit dans une base SQLITE EN MÉMOIRE (migrations réelles), puis
 * le VRAI composant `FicheLapins` ou `FichePorcs` (clé `famille`) donne KPI, tableau mensuel, taux, traitements, libellé du mois, bandeau et transferts du jour.
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
use App\Livewire\Elevage\FichePorcs;
use App\Livewire\Elevage\FicheEscargots;
use App\Livewire\Elevage\FicheReproducteurs;
use App\Livewire\Elevage\FichePondeuses;
use App\Models\ModuleConfig;
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
            $produit = new Product(['sku' => 'S'.$p['id'], 'name' => $p['name'], 'category_id' => $categorie->id, 'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 2, 'stock_qty' => $p['stock_qty'] ?? 1, 'is_active' => true]);
            $produit->id = $p['id'];
            $produit->save();
        }
        foreach ($s['exercices'] as $e) {
            FiscalYear::create(['year' => $e['year'], 'start_date' => $e['start_date'], 'end_date' => $e['end_date'], 'status' => $e['status']]);
        }
        $especes = [];
        foreach ($s['lots'] as $l) {
            $especes[$l['species_code']] ??= LivestockSpecies::firstOrCreate(['code' => $l['species_code']], ['label' => ucfirst($l['species_code']), 'is_enabled' => true]);
            $lot = new LivestockLot(['code' => $l['code'], 'species_id' => $especes[$l['species_code']]->id, 'stage' => $l['stage'] ?? 'reproduction', 'initial_quantity' => $l['initial_quantity'], 'current_quantity' => $l['current_quantity'], 'created_date' => '2026-01-01', 'status' => $l['status'], 'is_active' => $l['is_active']]);
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

        if ($s['famille'] === 'escargots' && $s['module'] !== null) {
            ModuleConfig::create(['species_code' => 'helico', 'is_enabled' => $s['module']]);
        }
        $c = match ($s['famille']) { 'porcs' => new FichePorcs, 'escargots' => new FicheEscargots, 'reproducteurs' => new FicheReproducteurs, 'pondeuses' => new FichePondeuses, default => new FicheLapins };
        if ($c instanceof FicheReproducteurs) {
            // `mount()` : la bande choisie, sinon la première (`selectedLotId`) ; ici on ne monte pas le composant.
            $c->selectedLotId = $s['bandeId'] ?? ($c->getLotsProperty()->first()?->id ?? '');
        }
        if ($c instanceof FicheEscargots) {
            $c->moduleEnabled = ModuleConfig::isEnabled('helico');   // `mount()` le lit ; ici on ne monte pas le composant
        }
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
                    // Lapins : `poids_general_g` (g) ; porcs : `round(avg × final / 1000, 1)` du Blade (Kg).
                    'poids_general_g' => $s['famille'] === 'porcs'
                        ? (($entry->weight_sample_avg_g && $entry->effectif_final) ? round(($entry->weight_sample_avg_g * $entry->effectif_final) / 1000, 1) : null)
                        : $entry->poids_general_g,
                    'effectif_final' => $entry->effectif_final,
                    'effectif_m' => $entry->effectif_m,
                    'mort' => $entry->mort,
                    // Pondeuses (colonnes du Blade) : effectif de début, œufs, taux de ponte et commercialisables.
                    'effectif_debut' => $entry->previousEffectif(),
                    'ponte_total' => $entry->ponte_total,
                    'ponte_casses' => $entry->ponte_casses,
                    'comm' => max(0, ($entry->ponte_total ?? 0) - ($entry->ponte_casses ?? 0)),
                    'taux_ponte' => $entry->previousEffectif() > 0 ? number_format(round((($entry->ponte_total ?? 0) / $entry->previousEffectif()) * 100, 1), 1) : null,
                ],
                'traitements' => method_exists($c, 'traitementsDuJour') ? $c->traitementsDuJour($jour, $entry) : null,   // pas de colonne de traitements chez les reproducteurs
            ];
        }
        $sortie[$i] = [
            'kpis' => $kpis,
            'jours' => $jours,
            'libelleMois' => $c->getLibelleMoisProperty(),
            'estMoisCourant' => $c->getEstMoisCourantProperty(),
            'bandeau' => $c->getBandeauLectureSeuleProperty(),
            'transferts' => $c->getTransfertsDuJourProperty(),
            'bande' => $c instanceof FicheReproducteurs ? $c->getSelectedLotProperty()?->id : $c->getBandeProperty()?->id,
        ];
    } finally {
        DB::rollBack();
        Carbon::setTestNow();
    }
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION);
