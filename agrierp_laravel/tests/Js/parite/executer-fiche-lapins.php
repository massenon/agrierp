<?php

/**
 * PWA-3 (fiche lapins) — PARITÉ EXÉCUTÉE de `resources/js/hors-ligne/fiche-lapins-calculs.js` : rejoue sur le VRAI
 * `CategorieRationLapin` et le VRAI `FicheLapins::getProvendeCalculationProperty` les cas que `tests/Js/parite-fiche-lapins.test.mjs`
 * envoie en JSON. Aucune base de données.
 *
 *   php tests/Js/parite/executer-fiche-lapins.php < cas.json
 */

putenv('APP_ENV=testing');
$racine = dirname(__DIR__, 3);
require $racine.'/vendor/autoload.php';
$app = require $racine.'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Livewire\Elevage\FicheLapins;
use App\Models\FeedRationStandard;
use App\Support\CategorieRationLapin;

$entree = json_decode(stream_get_contents(STDIN), true);
$sortie = ['cles' => [], 'provendes' => []];

foreach ($entree['libelles'] as $i => $libelle) {
    $sortie['cles'][$i] = CategorieRationLapin::cle($libelle);
}

foreach ($entree['provendes'] as $i => $cas) {
    $rations = collect(array_map(fn ($r) => new FeedRationStandard(['species_code' => 'cuniculture', 'stage_label' => $r['stage_label'], 'ration_g_per_day' => $r['ration_g_per_day']]), $cas['rations']));
    $cat = $cas['cat'];
    $composant = new class($rations, $cat) extends FicheLapins {
        public function __construct(private $rationsFixes, private array $catFixes)
        {
        }

        public function getRationStandardsProperty()
        {
            return $this->rationsFixes;
        }

        public function getCategoriesJourProperty(): array
        {
            return $this->catFixes;
        }
    };
    $sortie['provendes'][$i] = $composant->getProvendeCalculationProperty();
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION);
