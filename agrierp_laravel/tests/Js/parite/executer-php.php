<?php

/**
 * PWA-1 — PARITÉ EXÉCUTÉE : rejoue sur le VRAI code PHP les cas que `tests/Js/parite-php.test.mjs` envoie en JSON
 * (entrée standard), et rend les résultats (sortie standard). Aucune base de données n'est nécessaire.
 *
 *   php tests/Js/parite/executer-php.php < cas.json
 */

putenv('APP_ENV=testing');
putenv('DB_CONNECTION=sqlite');
putenv('DB_DATABASE=:memory:');
$_ENV['APP_ENV'] = 'testing';

$racine = dirname(__DIR__, 3);
require $racine.'/vendor/autoload.php';
$app = require $racine.'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Actions\RecordSaleAccountingEntryAction;
use App\Http\Controllers\Api\SyncController;
use App\Livewire\Ventes\PosInterface;
use App\Models\Product;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Services\Mecef\ChoixFactureService;
use App\Services\TvaSettingService;
use App\Support\MotifsRefusPush;
use Illuminate\Validation\ValidationException;

$entree = json_decode(stream_get_contents(STDIN), true);
$sortie = [];

// La TVA : l'exploitation est assujettie ou non selon le cas, sans base (le service est remplacé).
$GLOBALS['tva_active'] = true;
$app->instance(TvaSettingService::class, new class extends TvaSettingService {
    public function active(): bool { return $GLOBALS['tva_active']; }
});

// 1. Caisse web : sous-total, total, prix unitaire.
foreach ($entree['ventes'] as $i => $cas) {
    $caisse = new PosInterface();
    $caisse->cart = array_map(fn ($l) => ['product_id' => 'p', 'montant' => $l['montant'], 'qty' => $l['qty']], $cas['lignes']);
    $caisse->discount = (float) $cas['remise'];
    $res = [
        'subtotal' => $caisse->getSubtotalProperty(),
        'total' => $caisse->getTotalProperty(),
        'unit_prices' => array_map(fn ($l) => $l['qty'] > 0 ? round($l['montant'] / $l['qty'], 2) : 0, $cas['lignes']),
    ];

    // 2. TVA : `RecordSaleAccountingEntryAction::ventilerHtEtTva` (privée) sur des modèles non enregistrés.
    $GLOBALS['tva_active'] = (bool) $cas['tva_active'];
    $sale = new Sale(['discount' => $cas['remise']]);
    $sale->total = max(0, array_sum(array_column($cas['lignes'], 'montant')) - $cas['remise']);
    $lignes = collect();
    foreach ($cas['lignes'] as $l) {
        $ligne = new SaleLine(['qty' => $l['qty'], 'unit_price' => 0, 'manual_total_amount' => $l['montant']]);
        $ligne->setRelation('product', new Product(['tva_rate' => $l['tva_rate']]));
        $lignes->push($ligne);
    }
    $sale->setRelation('lines', $lignes);
    $sale->setRelation('devis', null);
    $m = new ReflectionMethod(RecordSaleAccountingEntryAction::class, 'ventilerHtEtTva');
    $m->setAccessible(true);
    [$ht, $tva] = $m->invoke(app(RecordSaleAccountingEntryAction::class), $sale);
    $res['ht'] = $ht;
    $res['tva'] = $tva;

    // 3. Le serveur accepte-t-il le total que la caisse calcule ? (`verifierCoherenceDuTotal`, privée)
    $v = new ReflectionMethod(SyncController::class, 'verifierCoherenceDuTotal');
    $v->setAccessible(true);
    $payload = [
        'discount' => $cas['remise'],
        'total' => $cas['total_js'],
        'lines' => array_map(fn ($l) => ['manual_total_amount' => $l['montant']], $cas['lignes']),
    ];
    try {
        $v->invoke((new ReflectionClass(SyncController::class))->newInstanceWithoutConstructor(), $payload);
        $res['total_accepte'] = true;
    } catch (ValidationException $e) {
        $res['total_accepte'] = false;
    }
    $sortie['ventes'][$i] = $res;
}

// 4. Choix de facture : le vrai `ChoixFactureService`.
foreach ($entree['factures'] as $i => $donnees) {
    try {
        $sortie['factures'][$i] = ['ok' => true, 'choix' => app(ChoixFactureService::class)->valider($donnees)];
    } catch (ValidationException $e) {
        $sortie['factures'][$i] = ['ok' => false, 'champ' => array_key_first($e->errors()), 'motif' => $e->errors()[array_key_first($e->errors())][0]];
    }
}

// 5. Motifs : constantes du serveur et phrases littérales de la caisse web.
$caisseSource = file_get_contents($racine.'/app/Livewire/Ventes/PosInterface.php');
$sortie['motifs'] = [
    'panierVide' => str_contains($caisseSource, "'Le panier est vide.'") ? 'Le panier est vide.' : null,
    'venteACredit' => str_contains($caisseSource, "'Une vente à crédit exige un client : choisissez-le dans la liste ou créez-le avec le bouton « + ».'")
        ? 'Une vente à crédit exige un client : choisissez-le dans la liste ou créez-le avec le bouton « + ».' : null,
    'factureType' => ChoixFactureService::MOTIF_TYPE,
    'factureNom' => ChoixFactureService::MOTIF_NOM,
    'factureIfu' => ChoixFactureService::MOTIF_IFU,
    'factureAib' => ChoixFactureService::MOTIF_AIB,
    'serveurCredit' => MotifsRefusPush::venteSansClient('credit'),
];

// 6. Motifs de validation d'une ligne (les messages français du serveur, mêmes règles que `pushSales`).
$val = function (array $ligne) {
    $v = validator(['lines' => [$ligne]], [
        'lines.*.qty' => ['required', 'numeric', 'gt:0'],
        'lines.*.manual_total_amount' => ['required', 'numeric', 'min:0'],
    ], MotifsRefusPush::messages(), MotifsRefusPush::attributs());

    return $v->fails() ? $v->errors()->first() : null;
};
$sortie['validation_lignes'] = [
    'quantite' => $val(['qty' => 0, 'manual_total_amount' => 10]),
    'montant_negatif' => $val(['qty' => 1, 'manual_total_amount' => -1]),
    'montant_texte' => $val(['qty' => 1, 'manual_total_amount' => 'abc']),
];

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION);
