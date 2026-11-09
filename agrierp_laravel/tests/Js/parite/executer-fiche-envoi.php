<?php

/**
 * PWA-3 (fiche lapins, É4) — l'ENVOI d'une fiche saisie dans le navigateur, joué sur le VRAI `POST /api/sync/push` (clé
 * `livestock_daily_entries`, `SyncController::pushDailyEntries`, SQLite en mémoire, migrations réelles, compte « animalier »). Chaque
 * scénario porte l'état du serveur, la charge utile construite par `ficheEnJson` et le nombre d'envois : on rend la réponse, les fiches
 * obtenues (cascade comprise) et l'effectif de la bande après chaque envoi.
 *
 *   php tests/Js/parite/executer-fiche-envoi.php < scenarios.json
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

use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use App\Models\Permission;
use App\Models\Role;

foreach (['view-elevage', 'manage-elevage'] as $nom) {
    Permission::findOrCreate($nom, 'web');
}
Role::findOrCreate('animalier', 'web')->givePermissionTo(['view-elevage', 'manage-elevage']);
$utilisateur = User::create(['name' => 'Animalier', 'username' => 'animalier', 'email' => 'animalier@fermeolouwachegoun.com', 'password' => bcrypt('x'), 'is_active' => true]);
$utilisateur->assignRole('animalier');

$COLONNES = ['achat', 'ne', 'mort', 'vente', 'don', 'effectif_final', 'effectif_m', 'effectif_f', 'effectif_sevres', 'effectif_smeres', 'feed_qty_kg',
    'mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune', 'passage_sevre_jeune', 'weight_sample_avg_g',
    'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune', 'cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune'];
$etat = function (string $lotId) use ($COLONNES) {
    return LivestockDailyEntry::where('lot_id', $lotId)->orderBy('entry_date')->get()->map(function ($f) use ($COLONNES) {
        $o = ['entry_date' => $f->entry_date->format('Y-m-d')];
        foreach ($COLONNES as $c) {
            $o[$c] = $f->{$c} === null ? null : (float) $f->{$c};
        }

        return $o;
    })->all();
};
$envoyer = function (array $charge) use ($utilisateur, $app) {
    Sanctum::actingAs($utilisateur, ['*']);
    $requete = Request::create('/api/sync/push', 'POST', [], [], [], ['CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json'],
        json_encode(['device_id' => 'pwa-test', 'livestock_daily_entries' => $charge]));
    $reponse = $app->handle($requete);

    return ['statut' => $reponse->getStatusCode(), 'json' => json_decode($reponse->getContent(), true)];
};

$entree = json_decode(stream_get_contents(STDIN), true);
$sortie = [];

foreach ($entree['scenarios'] as $i => $s) {
    DB::beginTransaction();
    try {
        Carbon::setTestNow(Carbon::parse($s['aujourdhui'].' 12:00:00', 'Africa/Porto-Novo'));
        $code = $s['espece'] ?? 'cuniculture';
        $espece = LivestockSpecies::firstOrCreate(['code' => $code], ['label' => ucfirst($code), 'is_enabled' => true]);
        foreach ($s['exercices'] as $e) {
            FiscalYear::create(['year' => $e['year'], 'start_date' => $e['start_date'], 'end_date' => $e['end_date'], 'status' => $e['status']]);
        }
        $lot = new LivestockLot(['code' => $s['lot']['code'], 'species_id' => $espece->id, 'stage' => $s['lot']['stage'], 'initial_quantity' => $s['lot']['initial_quantity'], 'current_quantity' => $s['lot']['current_quantity'], 'created_date' => '2026-01-01', 'status' => 'actif', 'is_active' => true]);
        $lot->id = $s['lot']['id'];
        $lot->save();
        foreach ($s['fiches'] as $f) {
            $fiche = new LivestockDailyEntry;
            $fiche->forceFill($f);
            $fiche->save();
        }
        $envois = [];
        for ($k = 0; $k < $s['envois']; $k++) {
            $r = $envoyer($s['charge']);
            $envois[] = [
                'statut' => $r['statut'],
                'reponse' => $r['json']['livestock_daily_entries'] ?? null,
                'fiches' => $etat($lot->id),
                'current_quantity' => (int) LivestockLot::find($lot->id)->current_quantity,
            ];
        }
        $sortie[$i] = $envois;
    } finally {
        DB::rollBack();
        Carbon::setTestNow();
    }
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION);
