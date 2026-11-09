<?php

/**
 * PWA-3 — PARITÉ EXÉCUTÉE de `resources/js/hors-ligne/effectif-categories.js` : rejoue sur le VRAI `EffectifParCategorieService`
 * (fonctions pures, aucune base) les cas que `tests/Js/parite-effectif.test.mjs` envoie en JSON.
 *
 *   php tests/Js/parite/executer-effectif.php < cas.json
 */

putenv('APP_ENV=testing');
$racine = dirname(__DIR__, 3);
require $racine.'/vendor/autoload.php';
$app = require $racine.'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Services\EffectifParCategorieService as S;

$entree = json_decode(stream_get_contents(STDIN), true);
$sortie = ['jours' => [], 'departs' => [], 'lots' => []];

foreach ($entree['jours'] as $i => $c) {
    try {
        $r = S::calculerJour($c['espece'], $c['veille'], $c['mouvements'], $c['total']);
        $sortie['jours'][$i] = [
            'repro' => $r->repro, 'sevre' => $r->sevre, 'jeune' => $r->jeune, 'sommeDifferente' => $r->sommeDifferente,
            'refus' => $r->refus, 'passageApplique' => $r->passageApplique, 'quatre' => $r->quatre,
            'passagesAppliques' => (object) $r->passagesAppliques,
        ];
    } catch (InvalidArgumentException $e) {
        $sortie['jours'][$i] = ['erreur' => $e->getMessage()];
    }
}

foreach ($entree['departs'] as $i => $c) {
    $sortie['departs'][$i] = S::verifierDepart($c['depart'], $c['total']);
}

foreach ($entree['lots'] as $i => $c) {
    $lot = new LivestockLot(['stage' => $c['stage']]);
    $lot->setRelation('species', $c['code'] === null ? null : new LivestockSpecies(['code' => $c['code']]));
    $sortie['lots'][$i] = [
        'espece' => S::especeDuLot($lot),
        'categorie_stade' => S::categorieDuStade($c['stage']),
        'categorie_bande' => S::categorieDeLaBande($lot),
        'depart' => S::departDepuisStade($lot, $c['total']),
    ];
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION);
