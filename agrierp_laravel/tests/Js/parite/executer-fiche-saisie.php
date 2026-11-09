<?php

/**
 * PWA-3 (fiche lapins, É3) — PARITÉ EXÉCUTÉE de `resources/js/hors-ligne/fiche-lapins-saisie.js` : chaque scénario (bandes, fiches, exercices,
 * barème, jour et saisie) est joué sur le VRAI composant `FicheLapins` (ouverture du jour puis `saveDay`, base SQLITE EN MÉMOIRE, migrations
 * réelles) : saisie rechargée à l'ouverture, refus (message du toast) ou fiches écrites et effectif de la bande après la cascade.
 *
 *   php tests/Js/parite/executer-fiche-saisie.php < scenarios.json
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
Illuminate\Support\Facades\Gate::before(fn ($utilisateur = null) => true);

use App\Livewire\Elevage\FicheLapins;
use App\Models\FeedRationStandard;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;

$COLONNES = ['achat', 'ne', 'mort', 'vente', 'don', 'effectif_final', 'effectif_m', 'effectif_f', 'effectif_sevres', 'effectif_smeres', 'feed_qty_kg',
    'mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune', 'passage_sevre_jeune', 'weight_sample_avg_g',
    'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune', 'cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune'];
$etatDesFiches = function (string $lotId) use ($COLONNES) {
    return LivestockDailyEntry::where('lot_id', $lotId)->orderBy('entry_date')->get()->map(function ($f) use ($COLONNES) {
        $o = ['entry_date' => $f->entry_date->format('Y-m-d')];
        foreach ($COLONNES as $c) {
            $o[$c] = $f->{$c} === null ? null : (float) $f->{$c};
        }

        return $o;
    })->all();
};

$entree = json_decode(stream_get_contents(STDIN), true);
$sortie = [];

foreach ($entree['scenarios'] as $i => $s) {
    DB::beginTransaction();
    try {
        Carbon::setTestNow(Carbon::parse($s['aujourdhui'].' 12:00:00', 'Africa/Porto-Novo'));
        session()->flush();
        $espece = LivestockSpecies::firstOrCreate(['code' => 'cuniculture'], ['label' => 'Cuniculture', 'is_enabled' => true]);
        foreach ($s['exercices'] as $e) {
            FiscalYear::create(['year' => $e['year'], 'start_date' => $e['start_date'], 'end_date' => $e['end_date'], 'status' => $e['status']]);
        }
        foreach ($s['rations'] as $r) {
            FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => $r['stage_label'], 'ration_g_per_day' => $r['ration_g_per_day'], 'is_active' => true]);
        }
        $lot = new LivestockLot(['code' => $s['lot']['code'], 'species_id' => $espece->id, 'stage' => $s['lot']['stage'], 'initial_quantity' => $s['lot']['initial_quantity'], 'current_quantity' => $s['lot']['current_quantity'], 'created_date' => '2026-01-01', 'status' => 'actif', 'is_active' => true]);
        $lot->id = $s['lot']['id'];
        $lot->save();
        foreach ($s['fiches'] as $f) {
            $fiche = new LivestockDailyEntry;
            $fiche->forceFill($f);
            $fiche->save();
        }

        $t = Livewire::test(FicheLapins::class)->set('bandeId', $lot->id)->set('selectedDate', $s['jour']);
        $c = $t->instance();
        $charge = [];
        foreach (['achat', 'ne', 'mortRepro', 'mortChair', 'mortLapereau', 'donRepro', 'donChair', 'donLapereau', 'passage', 'effectifM', 'effectifF', 'effectifSevres', 'effectifSmeres', 'departRepro', 'departSevre', 'departJeune', 'peseeTotal', 'mortAncienTotal', 'donAncienTotal'] as $p) {
            $charge[$p] = $c->{$p};
        }
        foreach ($s['saisie'] as $p => $v) {
            $t->set($p, $v);
        }
        $a = $t->instance();
        $cat = $a->getCategoriesJourProperty();
        $apercu = [
            'veille' => $a->getPreviousEffectifProperty(), 'effectifFinal' => $a->getEffectifFinalCalcProperty(), 'taux' => $a->getMortalityRateCalcProperty(),
            'avertissementMorts' => $a->getAvertissementMortsProperty(), 'poidsEstime' => $a->getPoidsMoyenEstimeProperty(),
            'provende_kg' => $a->getProvendeCalculationProperty()['total_kg'],
            'cat' => array_intersect_key($cat, array_flip(['mode', 'repro', 'sevre', 'jeune', 'motif', 'refus_passage', 'avertissements', 'depart_requis', 'depart_date'])),
        ];
        $t->call('saveDay');
        $toast = null;
        foreach ($t->effects['dispatches'] ?? [] as $d) {
            if (($d['name'] ?? '') === 'toast') {
                $toast = ['message' => $d['params']['message'] ?? null, 'type' => $d['params']['type'] ?? null];
            }
        }
        $sortie[$i] = [
            'charge' => $charge,
            'apercu' => $apercu,
            'toast' => $toast,
            'fiches' => $etatDesFiches($lot->id),
            'current_quantity' => (int) LivestockLot::find($lot->id)->current_quantity,
        ];
    } finally {
        DB::rollBack();
        Carbon::setTestNow();
    }
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION);
