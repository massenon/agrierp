<?php

/**
 * Ticket S-T9 — CÔTÉ SERVEUR DE L'ESSAI À PLUSIEURS POSTES (`essai_multipostes.sh`, `test/essai_multipostes_test.dart`).
 *
 * Ce script démarre l'application Laravel de l'essai (mêmes variables d'environnement que le serveur lancé par
 * `essai_multipostes.sh` : `DB_CONNECTION`, `DB_DATABASE`…) et exécute UNE commande :
 *
 *   php essai_multipostes_serveur.php <dossier Laravel> preparer  <fichier instantané>
 *   php essai_multipostes_serveur.php <dossier Laravel> vente-web <json>
 *   php essai_multipostes_serveur.php <dossier Laravel> ration-web <json>
 *   php essai_multipostes_serveur.php <dossier Laravel> etat <fichier instantané> <fichier des saisies des postes>
 *
 * ⚠️⚠️ LES ÉCRITURES « AU WEB » PASSENT PAR LES VRAIS COMPOSANTS LIVEWIRE (`Livewire::test`, compte admin) : la vente
 * par `PosInterface` (panier, puis « Valider la Vente »), la ration par `ParametresElevage`, les bandes de l'essai par
 * `GestionBandes`. C'est le code que le navigateur exécute, contrôles d'autorisation compris — pas une insertion
 * directe, qui prouverait seulement que la base accepte une ligne.
 *
 * `etat` rend en JSON ce que le serveur détient à la fin de l'essai (et les invariants qu'il peut juger seul) ; le
 * test Dart compare avec ce que chaque poste a saisi. Une sortie JSON par commande, rien d'autre sur la sortie
 * standard (les journaux partent sur la sortie d'erreur).
 *
 * ⚠️ Jamais contre une base réelle : `essai_multipostes.sh` crée une base dédiée, et le test Dart refuse de tourner
 * sans les variables qu'il pose.
 */

if ($argc < 3) {
    fwrite(STDERR, "Usage : php essai_multipostes_serveur.php <dossier Laravel> <commande> [arguments]\n");
    exit(2);
}

[$_, $laravel, $commande] = $argv;
$arguments = array_slice($argv, 3);

require $laravel.'/vendor/autoload.php';
$app = require $laravel.'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Models\AccountingEntry;
use App\Models\FeedRationStandard;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\Sale;
use App\Models\User;
use App\Services\FusionReferentielsService;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;

/** Le compte du « web » : l'administrateur du jeu de démonstration. */
function administrateur(): User
{
    return User::where('username', 'admin')->firstOrFail();
}

function sortie(array $donnees): never
{
    echo json_encode($donnees, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION);
    exit(0);
}

function echec(string $message): never
{
    fwrite(STDERR, $message."\n");
    echo json_encode(['erreur' => $message], JSON_UNESCAPED_UNICODE);
    exit(1);
}

/** Erreurs de validation et toasts d'un composant testé, pour un message d'échec lisible. */
function diagnostic($composant): string
{
    $erreurs = $composant->errors()->toArray();

    return $erreurs === [] ? '' : json_encode($erreurs, JSON_UNESCAPED_UNICODE);
}

/** Jours de la fenêtre de l'essai, du plus ancien à aujourd'hui (fuseau de l'application). */
function fenetre(int $jours): array
{
    $liste = [];
    for ($k = $jours; $k >= 0; $k--) {
        $liste[] = now()->subDays($k)->format('Y-m-d');
    }

    return $liste;
}

/** Stock par produit, grand livre par produit (entrées − sorties), fiches de la fenêtre, ventes connues. */
function instantane(array $lots): array
{
    $stocks = [];
    foreach (Product::all(['id', 'name', 'stock_qty']) as $p) {
        $stocks[$p->id] = ['nom' => $p->name, 'stock' => round((float) $p->stock_qty, 2)];
    }

    $livre = DB::table('stock_movements')
        ->selectRaw("product_id, SUM(CASE WHEN type = 'entree' THEN quantity WHEN type = 'sortie' THEN -quantity ELSE 0 END) AS solde, COUNT(*) AS n")
        ->groupBy('product_id')->get();
    foreach ($livre as $l) {
        $stocks[$l->product_id]['livre'] = round((float) $l->solde, 2);
        $stocks[$l->product_id]['mouvements'] = (int) $l->n;
    }

    $fiches = [];
    foreach (LivestockDailyEntry::whereIn('lot_id', $lots)->whereDate('entry_date', '>=', now()->subDays(12)->format('Y-m-d'))->get() as $f) {
        $fiches[$f->lot_id.'|'.$f->entry_date->format('Y-m-d')] = [
            'id' => $f->id,
            'vente' => (int) $f->vente,
            'mort' => (int) $f->mort,
            'effectif_final' => (int) $f->effectif_final,
        ];
    }

    return [
        'pris_le' => now()->toIso8601String(),
        'stocks' => $stocks,
        'fiches' => $fiches,
        'ventes' => Sale::pluck('id')->all(),
        'lots' => $lots,
    ];
}

switch ($commande) {
    // ── Avant l'essai : deux bandes créées AU WEB (sans fiche dans la fenêtre), puis l'instantané ──────────────────
    case 'preparer':
        [$fichierInstantane] = $arguments + [null];
        if ($fichierInstantane === null) {
            echec('preparer : fichier de l\'instantané manquant.');
        }

        $espece = LivestockSpecies::where('code', 'aviculture')->firstOrFail();
        $produit = Product::where('species_id', $espece->id)->where('name', 'like', 'Poulet goliath%')->firstOrFail();

        $bandes = [];
        foreach (['ESSAI-A' => 300, 'ESSAI-B' => 200] as $code => $effectif) {
            $composant = Livewire::actingAs(administrateur())
                ->test(App\Livewire\Elevage\GestionBandes::class)
                ->call('newLot')
                // L'espèce d'abord : `updatedSpeciesId` propose un code, que le nôtre remplace ensuite.
                ->set('species_id', $espece->id)
                ->set('code', $code)
                ->set('stage', 'engraissement')
                ->set('product_id', $produit->id)
                ->set('created_date', now()->subDays(10)->format('Y-m-d'))
                ->set('quantity', $effectif)
                ->call('saveLot');

            $lot = LivestockLot::where('code', $code)->first();
            if ($lot === null) {
                echec("Bande {$code} non créée au web : ".diagnostic($composant));
            }
            $bandes[$code] = $lot->id;
        }

        // Ticket S-T10 — 30 sacs de piment entrés AU WEB (« Ajouter Stock » de Gestion des Stocks) : le produit que le
        // bureau comptera pendant que le web et la caisse 1 en vendent. Le jeu de démonstration l'a épuisé.
        $piment = Product::where('name', 'like', 'Piment frais%')->firstOrFail();
        $ajout = Livewire::actingAs(administrateur())
            ->test(App\Livewire\Stocks\GestionStocks::class)
            ->call('openAddStockModal')
            // Daté AVANT la fenêtre de l'essai (comme les bandes) : l'essai rejoue ses journées dans le passé, et un
            // ajout daté d'aujourd'hui serait, pour le grand livre, POSTÉRIEUR au comptage simulé d'hier.
            ->set('addDate', now()->subDays(10)->format('Y-m-d'))
            ->set('addProductId', $piment->id)
            ->set('addQty', 30)
            ->call('submitAjouterStock');
        if ((float) $piment->fresh()->stock_qty < 30) {
            echec('Ajout de stock du piment non enregistré au web : '.diagnostic($ajout));
        }

        $suivies = array_values(array_merge(
            $bandes,
            LivestockLot::where('status', 'actif')->whereNotIn('code', array_keys($bandes))->pluck('id')->all(),
        ));

        file_put_contents($fichierInstantane, json_encode(instantane($suivies), JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION));

        sortie(['bandes' => $bandes, 'produit_bande' => $produit->id]);

    // ── Une vente AU WEB, par la caisse web (PosInterface), éventuellement antérieure (`jour`) ─────────────────────
    case 'vente-web':
        $p = json_decode($arguments[0] ?? '{}', true);
        $avant = Sale::pluck('id')->all();

        $caisse = Livewire::actingAs(administrateur())->test(App\Livewire\Ventes\PosInterface::class);
        if (! empty($p['jour'])) {
            $caisse->set('dateVente', $p['jour']);
        }
        $caisse->call('selectProduct', $p['produit'])
            ->set('weightQty', (int) $p['quantite'])
            ->set('weightPrice', (float) $p['montant'])
            ->set('weightLotId', $p['lot'] ?? '')
            ->call('confirmWeightAdd')
            ->set('paymentMode', 'especes')
            ->set('cashReceived', (float) $p['montant'])
            ->call('validateSale');

        $nouvelles = Sale::whereNotIn('id', $avant)->pluck('id')->all();
        if (count($nouvelles) !== 1) {
            echec('Vente web non enregistrée ('.count($nouvelles).' vente(s) nouvelle(s)) : '.diagnostic($caisse));
        }

        // Ticket S-T10 — le stock du produit au serveur JUSTE APRÈS la vente : ce que les rayons contiennent (l'essai
        // en déduit la quantité que le bureau compte, alors que son stock local ignore encore cette vente).
        sortie(['vente' => $nouvelles[0], 'stock_apres' => round((float) Product::findOrFail($p['produit'])->stock_qty, 2)]);

    // ── Une ration modifiée AU WEB (Paramètres Élevage) ───────────────────────────────────────────────────────────
    case 'ration-web':
        $p = json_decode($arguments[0] ?? '{}', true);
        $ration = FeedRationStandard::where('is_active', true)
            ->where('species_code', $p['espece'] ?? 'aviculture')
            ->orderBy('stage_label')->firstOrFail();

        $composant = Livewire::actingAs(administrateur())
            ->test(App\Livewire\Elevage\ParametresElevage::class)
            ->call('editRation', $ration->id)
            ->set('ration_grammes', (int) $p['grammes'])
            ->call('saveRation');

        if ((int) $ration->fresh()->ration_g_per_day !== (int) $p['grammes']) {
            echec('Ration non modifiée au web : '.diagnostic($composant));
        }

        sortie(['ration' => $ration->id, 'grammes' => (int) $p['grammes']]);

    // ── Après l'essai : ce que le serveur détient, et ses invariants propres ──────────────────────────────────────
    case 'etat':
        [$fichierInstantane, $fichierSaisies] = $arguments + [null, null];
        $avant = json_decode((string) file_get_contents($fichierInstantane), true);
        $saisies = json_decode((string) file_get_contents($fichierSaisies), true) ?: [];
        $apres = instantane($avant['lots']);
        $fusion = app(FusionReferentielsService::class);

        // 1. Présence au serveur de chaque saisie des postes (identifiant du poste, ou celui de la fusion S-T5).
        $tables = [
            'sales' => 'sales',
            'veterinary_records' => 'veterinary_records', 'customers' => 'customers', 'suppliers' => 'suppliers',
            'purchases' => 'purchases', 'customer_advances' => 'customer_advances',
            'livestock_transfers' => 'livestock_transfers',
        ];
        $presence = [];
        foreach ($tables as $cle => $table) {
            foreach ($saisies[$cle] ?? [] as $id) {
                $idServeur = in_array($table, ['customers', 'suppliers'], true) ? ($fusion->idServeur($table, $id) ?? $id) : $id;
                $presence[$cle][$id] = DB::table($table)->where('id', $idServeur)->count();
            }
        }
        // Fiches : par leur clé naturelle (bande, jour) — une fiche fusionnée (S-T9) a pris l'identifiant du serveur.
        foreach ($saisies['fiches'] ?? [] as $cle) {
            [$lot, $jour] = explode('|', $cle);
            $presence['fiches'][$cle] = DB::table('livestock_daily_entries')->where('lot_id', $lot)->whereDate('entry_date', $jour)->count();
        }
        // Ajustements : rejoués par `AdjustStockAction`, retrouvés par `stock_movements.reference_id`.
        foreach ($saisies['stock_adjustments'] ?? [] as $id) {
            $presence['stock_adjustments'][$id] = DB::table('stock_movements')->where('reference_id', $id)->count();
        }

        // 2. Doublons.
        $doublons = [
            'fiches_bande_jour' => DB::table('livestock_daily_entries')
                ->selectRaw('lot_id, entry_date, COUNT(*) AS n')->groupBy('lot_id', 'entry_date')
                ->havingRaw('COUNT(*) > 1')->get()->all(),
            'mouvements_par_reference' => DB::table('stock_movements')
                ->selectRaw('reference_type, reference_id, product_id, COUNT(*) AS n')
                ->whereNotNull('reference_id')->whereIn('reference_type', ['inventaire', 'manual_addition'])
                ->groupBy('reference_type', 'reference_id', 'product_id')->havingRaw('COUNT(*) > 1')->get()->all(),
            'mouvements_de_vente' => DB::table('stock_movements')
                ->selectRaw('reference_id, product_id, COUNT(*) AS n')
                ->where('reference_type', 'sale')->whereNotIn('reference_id', $avant['ventes'])
                ->groupBy('reference_id', 'product_id')->get()
                ->filter(function ($m) {
                    $lignes = DB::table('sale_lines')->where('sale_id', $m->reference_id)->where('product_id', $m->product_id)->count();

                    return (int) $m->n !== $lignes;
                })->values()->all(),
        ];
        $cles = [];
        foreach (['customers', 'suppliers'] as $table) {
            $cles[$table] = [];
            foreach (DB::table($table)->where('is_active', true)->get(['id', 'name', 'phone']) as $fiche) {
                $cle = $fusion->cleNaturelle($table, (array) $fiche);
                if ($cle !== null) {
                    $cles[$table][$cle][] = $fiche->id;
                }
            }
            $cles[$table] = array_filter($cles[$table], fn ($ids) => count($ids) > 1);
        }
        $doublons['clients_meme_cle'] = $cles['customers'];
        $doublons['fournisseurs_meme_cle'] = $cles['suppliers'];

        // 3. Ventes sur les fiches (15.30) : pour chaque (bande, jour) suivi, la vente AJOUTÉE à la fiche depuis
        // l'instantané doit être la somme des quantités des NOUVELLES ventes (postes et web) — ni deux fois, ni zéro.
        $ventesParFiche = DB::table('sale_lines')
            ->join('sales', 'sales.id', '=', 'sale_lines.sale_id')
            ->whereNotIn('sales.id', $avant['ventes'])
            ->where('sales.status', 'validee')
            ->whereIn('sale_lines.lot_id', $avant['lots'])
            ->selectRaw('sale_lines.lot_id AS lot, DATE(COALESCE(sales.sold_at, sales.created_at)) AS jour, SUM(sale_lines.qty) AS qte')
            ->groupBy('lot', 'jour')->get();
        $fichesVente = [];
        foreach ($ventesParFiche as $v) {
            $cle = $v->lot.'|'.$v->jour;
            $fichesVente[$cle] = [
                'attendu' => (int) round((float) $v->qte),
                'avant' => $avant['fiches'][$cle]['vente'] ?? 0,
                'apres' => $apres['fiches'][$cle]['vente'] ?? null,
            ];
        }
        foreach ($apres['fiches'] as $cle => $f) {
            if (! isset($fichesVente[$cle]) && $f['vente'] !== ($avant['fiches'][$cle]['vente'] ?? 0)) {
                $fichesVente[$cle] = ['attendu' => 0, 'avant' => $avant['fiches'][$cle]['vente'] ?? 0, 'apres' => $f['vente']];
            }
        }

        // 4. Stock = grand livre, produit par produit (en écart par rapport à l'instantané : le jeu de démonstration
        // peut porter un stock d'ouverture sans mouvement).
        $stocks = [];
        foreach ($apres['stocks'] as $id => $s) {
            $a = $avant['stocks'][$id] ?? ['stock' => 0.0, 'livre' => 0.0];
            $stocks[$id] = [
                'nom' => $s['nom'],
                // Ticket S-T10 — le stock final, comparé à l'attendu de l'inventaire compté au bureau.
                'stock' => $s['stock'],
                'ecart_ouverture' => round(($a['stock'] ?? 0) - ($a['livre'] ?? 0), 2),
                'ecart_fin' => round(($s['stock'] ?? 0) - ($s['livre'] ?? 0), 2),
            ];
        }

        // 5. Journal comptable.
        $journal = DB::table('accounting_entry_lines')->selectRaw('ROUND(SUM(debit), 2) AS d, ROUND(SUM(credit), 2) AS c')->first();
        $desequilibrees = DB::table('accounting_entry_lines')
            ->selectRaw('entry_id, ROUND(SUM(debit), 2) AS d, ROUND(SUM(credit), 2) AS c')
            ->groupBy('entry_id')->havingRaw('ROUND(SUM(debit), 2) <> ROUND(SUM(credit), 2)')->get()->all();
        $ventesSansEcriture = Sale::whereNotIn('id', $avant['ventes'])
            ->where('status', 'validee')->whereNull('accounting_entry_id')->pluck('id')->all();

        sortie([
            'presence' => $presence,
            'doublons' => $doublons,
            'fiches_vente' => $fichesVente,
            'fiches_apres' => $apres['fiches'],
            'stocks' => $stocks,
            'journal' => ['debit' => (float) $journal->d, 'credit' => (float) $journal->c, 'desequilibrees' => $desequilibrees],
            'ventes_sans_ecriture' => $ventesSansEcriture,
            'ventes_nouvelles' => Sale::whereNotIn('id', $avant['ventes'])->count(),
            'ecritures' => AccountingEntry::count(),
        ]);

    default:
        echec("Commande inconnue : {$commande}");
}
