<?php

/**
 * PWA-3 (fiche lapins, É3) — PARITÉ EXÉCUTÉE de `resources/js/hors-ligne/fiche-lapins-saisie.js` : chaque scénario (bandes, fiches, exercices,
 * barème, jour et saisie) est joué sur le VRAI composant `FicheLapins` ou `FichePorcs` (clé `famille` ; ouverture du jour puis `saveDay`, base SQLITE EN MÉMOIRE, migrations
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
use App\Livewire\Elevage\FichePorcs;
use App\Livewire\Elevage\FicheEscargots;
use App\Livewire\Elevage\FicheReproducteurs;
use App\Models\ModuleConfig;
use App\Models\FeedRationStandard;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\FieldSurveyEntry;
use App\Models\Product;
use App\Models\ProductCategory;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;

$COLONNES = ['achat', 'ne', 'mort', 'vente', 'don', 'effectif_final', 'effectif_m', 'effectif_f', 'effectif_sevres', 'effectif_smeres', 'feed_qty_kg',
    'mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune', 'passage_sevre_jeune', 'weight_sample_avg_g',
    'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune', 'cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune', 'ponte_total', 'vente_repro', 'vente_sevre', 'vente_jeune'];
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
        $porcs = ($s['famille'] ?? 'lapins') === 'porcs';
        $egot = ($s['famille'] ?? 'lapins') === 'escargots';
        $repro = ($s['famille'] ?? 'lapins') === 'reproducteurs';
        $code = $egot ? 'helico' : ($repro ? 'aviculture' : ($porcs ? 'porciculture' : 'cuniculture'));
        if ($egot) {
            ModuleConfig::create(['species_code' => 'helico', 'is_enabled' => true]);   // sinon la fiche n'offre aucune bande
        }
        $espece = LivestockSpecies::firstOrCreate(['code' => $code], ['label' => ucfirst($code), 'is_enabled' => true]);
        foreach ($s['exercices'] as $e) {
            FiscalYear::create(['year' => $e['year'], 'start_date' => $e['start_date'], 'end_date' => $e['end_date'], 'status' => $e['status']]);
        }
        if ($repro) {
            // La migration VOL-1 sème Reproducteur 130 / Jeune 80 / Poussin 30 : le scénario porte SON barème, sans ces lignes.
            FeedRationStandard::where('species_code', $code)->delete();
        }
        foreach ($s['rations'] as $r) {
            FeedRationStandard::create(['species_code' => $code, 'stage_label' => $r['stage_label'], 'ration_g_per_day' => $r['ration_g_per_day'], 'is_active' => true]);
        }
        // É5 : produit de provende, types de provende (poids du sac) et règle de terrain, pour l'autonomie alimentaire de la fiche.
        $p = $s['provende']['produit'];
        if ($p !== null) {
            $produit = new Product(['sku' => 'SP', 'name' => $p['name'], 'category_id' => ProductCategory::create(['label' => 'Parité', 'is_active' => true])->id, 'unit' => $p['unit'], 'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 2, 'stock_qty' => $p['stock_qty'], 'is_active' => true]);
            $produit->id = $p['id'];
            $produit->species_id = $espece->id;
            $produit->save();
        }
        foreach ($s['provende']['feed_types'] as $f) {
            DB::table('feed_types')->insert(['id' => $f['id'], 'name' => 'T', 'standard_bag_weight_kg' => $f['standard_bag_weight_kg'], 'price_per_kg' => 1, 'is_active' => true, 'created_at' => now(), 'updated_at' => now()]);
        }
        if ($s['provende']['releve'] !== null) {
            $r = new FieldSurveyEntry;
            $r->forceFill(['type' => 'delai_regle', 'label' => 'Règle', 'data' => $s['provende']['releve']['data'], 'status' => $s['provende']['releve']['status'], 'is_active' => true]);
            $r->id = $s['provende']['releve']['id'];
            $r->save();
        }
        $lot = new LivestockLot(['code' => $s['lot']['code'], 'species_id' => $espece->id, 'stage' => $s['lot']['stage'], 'initial_quantity' => $s['lot']['initial_quantity'], 'current_quantity' => $s['lot']['current_quantity'], 'created_date' => '2026-01-01', 'status' => 'actif', 'is_active' => true]);
        $lot->id = $s['lot']['id'];
        $lot->save();
        foreach ($s['fiches'] as $f) {
            $fiche = new LivestockDailyEntry;
            $fiche->forceFill($f);
            $fiche->save();
        }

        // Noms internes de la saisie (ceux des emplacements de synchronisation) → propriétés du composant des porcs.
        $noms = $porcs ? ['mortChair' => 'mortMarchand', 'mortLapereau' => 'mortPorcelet', 'donChair' => 'donMarchand', 'donLapereau' => 'donPorcelet', 'effectifM' => 'effectifVerrats', 'effectifF' => 'effectifTruies', 'effectifSevres' => 'effectifPorcelets', 'effectifSmeres' => 'effectifEngraissement', 'peseeTotal' => 'peseeTotalKg'] : [];
        $t = Livewire::test($egot ? FicheEscargots::class : ($repro ? FicheReproducteurs::class : ($porcs ? FichePorcs::class : FicheLapins::class)))->set($repro ? 'selectedLotId' : 'bandeId', $lot->id)->set('selectedDate', $s['jour']);
        $c = $t->instance();
        $charge = [];
        $proprietes = $repro
            ? ['achat', 'oeufsCouves', 'poussinsNes', 'mortRepro', 'mortPoulet', 'mortPoussin', 'donRepro', 'donPoulet', 'donPoussin', 'passage', 'departRepro', 'departSevre', 'departJeune', 'mortEnregistre', 'donEnregistre', 'peseeTotal']
            : ($egot
            ? ['achat', 'oeufsTerre', 'naissainsNes', 'mortBorde', 'mortEngraissement', 'mortNaissain', 'donBorde', 'donEngraissement', 'donNaissain', 'mortEnregistre', 'donEnregistre', 'effectifNaissains', 'effectifEngraissement', 'effectifBordes', 'peseeTotal']
            : ['achat', 'ne', 'mortRepro', 'mortChair', 'mortLapereau', 'donRepro', 'donChair', 'donLapereau', 'passage', 'effectifM', 'effectifF', 'effectifSevres', 'effectifSmeres', 'departRepro', 'departSevre', 'departJeune', 'peseeTotal', 'mortAncienTotal', 'donAncienTotal']);
        foreach ($proprietes as $p) {
            $charge[$p] = $c->{$noms[$p] ?? $p};
        }
        foreach ($s['saisie'] as $p => $v) {
            $t->set($noms[$p] ?? $p, $v);
        }
        $a = $t->instance();
        if ($repro) {
            $x = $a->getFeedAutonomyProperty();
            $cat = $a->getCategoriesJourProperty();
            $apercu = ['veille' => $a->getPreviousEffectifProperty(), 'vente' => $a->getVenteDuJourProperty(), 'ventes' => $a->getVentesDuJourProperty(), 'effectifFinal' => $a->getEffectifFinalCalcProperty(), 'taux' => $a->getMortalityRateCalcProperty(),
                'eclosion' => $a->getEclosionRateCalcProperty(), 'avertissementMorts' => $a->getAvertissementMortsProperty(), 'poidsEstime' => $a->getPoidsMoyenEstimeProperty(),
                'ration' => $a->getRationnementProperty(),
                'autonomie' => ['available' => $x['available'], 'product' => isset($x['product']) ? $x['product']->id : null, 'stock_kg' => $x['stock_kg'] ?? null, 'autonomie_jours' => $x['autonomie_jours'] ?? null, 'critique' => $x['critique'] ?? null, 'rupture' => $x['rupture'] ?? null, 'inconnu' => $x['inconnu'] ?? false],
                'cat' => array_intersect_key($cat, array_flip(['mode', 'repro', 'sevre', 'jeune', 'motif', 'refus_passage', 'avertissements', 'depart_requis', 'depart_date', 'proposition']))];
        } elseif ($egot) {
            $apercu = ['veille' => $a->getPreviousEffectifProperty(), 'vente' => $a->getVenteDuJourProperty(), 'effectifFinal' => $a->getEffectifFinalCalcProperty(), 'taux' => $a->getMortalityRateCalcProperty(),
                'poidsEstime' => $a->getPoidsMoyenEstimeProperty(), 'eclosion' => $a->getEclosionRateCalcProperty()];
        } else {
        $cat = $a->getCategoriesJourProperty();
        $apercu = [
            'veille' => $a->getPreviousEffectifProperty(), 'effectifFinal' => $a->getEffectifFinalCalcProperty(), 'taux' => $a->getMortalityRateCalcProperty(),
            'avertissementMorts' => $a->getAvertissementMortsProperty(), 'poidsEstime' => $porcs ? $a->getPoidsMoyenEstimeKgProperty() : $a->getPoidsMoyenEstimeProperty(),
            'provende_kg' => $a->getProvendeCalculationProperty()['total_kg'],
            'autonomie' => (function () use ($a) { $x = $a->getFeedAutonomyProperty(); return ['available' => $x['available'], 'product' => isset($x['product']) ? $x['product']->id : null, 'stock_kg' => $x['stock_kg'] ?? null, 'autonomie_jours' => $x['autonomie_jours'] ?? null, 'critique' => $x['critique'] ?? null, 'rupture' => $x['rupture'] ?? null, 'inconnu' => $x['inconnu'] ?? false]; })(),
            'cat' => array_intersect_key($cat, array_flip(['mode', 'repro', 'sevre', 'jeune', 'motif', 'refus_passage', 'avertissements', 'depart_requis', 'depart_date'])),
        ];
        }
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
