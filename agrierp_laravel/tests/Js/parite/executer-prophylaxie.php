<?php

/**
 * PWA-3 (fiche lapins) — PARITÉ EXÉCUTÉE de `fiche-lapins-prophylaxie.js` contre le VRAI composant `FicheLapins` ou `FichePorcs` (clé `famille` ; `ProtocoleDuJourService`,
 * `ValidateProphylaxisTreatmentsAction`, `validerTraitements`) sur SQLite en mémoire : protocole du jour avant validation, message du toast,
 * soins et périodes de rémanence créés.
 *
 *   php tests/Js/parite/executer-prophylaxie.php < scenarios.json
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
use App\Livewire\Elevage\FicheReproducteurs;
use App\Livewire\Elevage\FichePondeuses;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;

$entree = json_decode(stream_get_contents(STDIN), true);
$sortie = [];
foreach ($entree['scenarios'] as $i => $s) {
    DB::beginTransaction();
    try {
        Carbon::setTestNow(Carbon::parse($s['aujourdhui'].' 12:00:00', 'Africa/Porto-Novo'));
        session()->flush();
        $porcs = ($s['famille'] ?? 'lapins') === 'porcs';
        $repro = ($s['famille'] ?? 'lapins') === 'reproducteurs';
        $pond = ($s['famille'] ?? 'lapins') === 'pondeuses';
        $code = ($repro || $pond) ? 'aviculture' : ($porcs ? 'porciculture' : 'cuniculture');
        $espece = LivestockSpecies::firstOrCreate(['code' => $code], ['label' => ucfirst($code), 'is_enabled' => true]);
        $lot = new LivestockLot(['code' => 'L'.$i, 'species_id' => $espece->id, 'stage' => $s['lot']['stage'], 'initial_quantity' => 40, 'current_quantity' => 40, 'created_date' => $s['lot']['created_date'], 'status' => 'actif', 'is_active' => true]);
        $lot->id = $s['lot']['id'];
        $lot->save();
        foreach ($s['evenements'] as $e) {
            DB::table('livestock_reproduction_events')->insert(['id' => $e['id'], 'lot_id' => $lot->id, 'mother_ref' => 'R1', 'saillie_date' => $e['saillie_date'], 'created_at' => now(), 'updated_at' => now()]);
        }
        foreach ($s['standards'] as $st) {
            DB::table('prophylaxis_schedule_standards')->insert($st + ['period_label' => 'P', 'created_at' => now(), 'updated_at' => now()]);
        }
        foreach ($s['soins'] as $so) {
            DB::table('veterinary_records')->insert(['id' => $so['id'], 'lot_id' => $lot->id, 'action_type' => $so['action_type'], 'record_date' => $so['record_date'], 'is_active' => $so['is_active'], 'created_at' => now(), 'updated_at' => now()]);
        }
        $t = Livewire::test($pond ? FichePondeuses::class : ($repro ? FicheReproducteurs::class : ($porcs ? FichePorcs::class : FicheLapins::class)))->set($repro ? 'selectedLotId' : 'bandeId', $lot->id)->set('selectedDate', $s['jour']);
        $p = $t->instance()->getProtocoleDuJourProperty();
        $avant = [
            'jourDeCycle' => $p->jourDeCycle, 'motif' => $p->motifIndetermine, 'calendaires' => $p->calendairesNonEvalues, 'etat' => $p->etat(), 'enAttente' => $p->enAttente(),
            'traitements' => $p->traitements->map(fn ($l) => ['id' => $l['standard']->id, 'deja' => $l['deja_administre']])->all(),
        ];
        $t->set('traitementsCoches', $s['coches'])->set('observations', $s['observations'])->call('validerTraitements');
        $toast = null;
        foreach ($t->effects['dispatches'] ?? [] as $d) {
            if (($d['name'] ?? '') === 'toast') {
                $toast = ['message' => $d['params']['message'] ?? null, 'type' => $d['params']['type'] ?? null];
            }
        }
        $soins = DB::table('veterinary_records')->orderBy('action_type')->orderBy('record_date')->get(['action_type', 'product_used', 'dose', 'symptomes', 'record_date', 'is_active'])
            ->map(fn ($r) => ['action_type' => $r->action_type, 'product_used' => $r->product_used, 'dose' => $r->dose, 'symptomes' => $r->symptomes, 'record_date' => substr($r->record_date, 0, 10), 'is_active' => (bool) $r->is_active])->all();
        $periodes = DB::table('veterinary_withdrawal_periods')->orderBy('product_used')->get(['product_used', 'start_date', 'withdrawal_days', 'end_date'])
            ->map(fn ($r) => ['product_used' => $r->product_used, 'start_date' => substr($r->start_date, 0, 10), 'withdrawal_days' => (int) $r->withdrawal_days, 'end_date' => substr($r->end_date, 0, 10)])->all();
        $sortie[$i] = ['avant' => $avant, 'toast' => $toast, 'soins' => $soins, 'periodes' => $periodes];
    } finally {
        DB::rollBack();
        Carbon::setTestNow();
    }
}
echo json_encode($sortie, JSON_UNESCAPED_UNICODE);
