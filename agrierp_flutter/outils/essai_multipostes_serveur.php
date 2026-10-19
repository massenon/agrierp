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
 * Ticket S-T12 — l'essai couvre tout ce qui se synchronise ; commandes ajoutées (toujours par les vrais composants) :
 *
 *   produit-web <json>        « Ajouter un Produit » (AjouterProduit) — le même produit qu'un poste crée (fusion S-T5)
 *   inventaire-web <json>     inventaire de Gestion des Stocks (validateAdjustment) : `ecart` = rayons − stock du serveur
 *   revoquer <poste>          « Révoquer l'appairage » (Paramètres → Postes & Appairage, CFG-1)
 *   desactiver|reactiver <identifiant>   archiver / réactiver un compte (Gestion des utilisateurs)
 *   demander <poste>          « Demander la synchronisation » d'un poste (S-T6) ; `demande <id>` : servie ?
 *   reinitialiser             « Réinitialisation des données » (15.50) : mode démonstration, mot de confirmation
 *   etat-reinitialise         lignes restantes dans chaque table d'activité, et la marque `data_reset_at`
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
use App\Services\ReinitialisationDonneesService;
use App\Services\SupplierRefundService;
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

/**
 * Ticket S-T12 — les soldes que l'essai compare entre les DEUX côtés de chaque flux : le grand livre (par code de
 * compte, écritures actives) et les tables métier (soldes des comptes de trésorerie par code, dettes fournisseurs,
 * créances clients, avances, créances sur fournisseurs). Une opération synchronisée doit les déplacer d'autant.
 */
function soldes(): array
{
    $livre = [];
    foreach (DB::table('accounting_entry_lines as l')
        ->join('accounting_entries as e', 'e.id', '=', 'l.entry_id')
        ->join('chart_of_accounts as c', 'c.id', '=', 'l.account_id')
        ->where('e.is_active', true)
        ->selectRaw('c.code AS code, ROUND(SUM(l.debit), 2) AS d, ROUND(SUM(l.credit), 2) AS c')
        ->groupBy('c.code')->get() as $l) {
        $livre[(string) $l->code] = round((float) $l->d - (float) $l->c, 2);
    }
    $tresorerie = [];
    foreach (DB::table('treasury_accounts')->selectRaw('account_code, ROUND(SUM(balance), 2) AS solde')->groupBy('account_code')->get() as $t) {
        $tresorerie[(string) $t->account_code] = round((float) $t->solde, 2);
    }
    $creancesFournisseurs = (float) DB::table('purchases')->whereNotNull('returned_at')->sum('supplier_credit')
        - (float) DB::table('supplier_refunds')->sum('applied_amount');

    return [
        'livre' => $livre,
        'tresorerie' => $tresorerie,
        'dettes_fournisseurs' => round((float) DB::table('payables')->selectRaw('SUM(amount - amount_paid) AS s')->value('s'), 2),
        'creances_clients' => round((float) DB::table('receivables')->selectRaw('SUM(amount - amount_paid) AS s')->value('s'), 2),
        'avances' => round((float) DB::table('customer_advances')->where('is_active', true)->selectRaw('SUM(amount - amount_used) AS s')->value('s'), 2),
        'creances_fournisseurs' => round($creancesFournisseurs, 2),
    ];
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
        'soldes' => soldes(),
    ];
}

/** Ticket S-T12 — un composant Livewire du web, au nom de l'administrateur. */
function web(string $composant)
{
    return Livewire::actingAs(administrateur())->test($composant);
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

        // ⚠️ Ticket S-T12 — DÉFAUT DÉCRIT, NON CORRIGÉ ICI : la caisse du web (`PosInterface::validateSale`) n'est pas
        // rejouée sur un interblocage MariaDB, contrairement à l'envoi des postes (S-T9, `DB::transaction(…, 3)`) — elle
        // verrouille le stock du produit puis la fiche, un envoi la fiche puis le stock. Sous les envois simultanés de
        // l'essai, la vente web a échoué deux fois (graine 314, `QueryException` venue de `Connection.php`). La rejouer
        // au serveur exige d'abord de sortir l'appel MeCeF de la transaction (il serait transmis deux fois). La
        // caissière revaliderait : l'aide fait de même pour un interblocage ou un délai de verrou (jamais pour une autre
        // erreur, rendue entière), au plus trois fois, et le dit (`interblocages`) — la transaction annulée n'a rien laissé.
        $interblocages = [];
        for ($essai = 1; ; $essai++) {
            try {
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
                break;
            } catch (Illuminate\Database\QueryException $e) {
                $interblocages[] = mb_substr($e->getMessage(), 0, 200);
                if ($essai >= 3 || ! preg_match('/1213|40001|Deadlock|1205/i', $e->getMessage())) {
                    echec('Vente web en échec : '.$e->getMessage());
                }
            }
        }

        // Ticket S-T12 — les postes envoient PENDANT la vente du web : une vente nouvelle n'est pas forcément la sienne.
        // Celle du web porte un identifiant du serveur (UUID ordonné, `HasUuids`), jamais un UUID v4 de poste, et une
        // ligne du produit vendu.
        $nouvelles = Sale::whereNotIn('id', $avant)
            ->whereHas('lines', fn ($l) => $l->where('product_id', $p['produit'])->where('qty', (int) $p['quantite']))
            ->pluck('id')
            ->filter(fn ($id) => substr((string) $id, 14, 1) !== '4')
            ->values()->all();
        if (count($nouvelles) !== 1) {
            echec('Vente web non enregistrée ('.count($nouvelles).' vente(s) nouvelle(s) du web) : '.diagnostic($caisse));
        }

        // Ticket S-T10 — le stock du produit au serveur JUSTE APRÈS la vente : ce que les rayons contiennent (l'essai
        // en déduit la quantité que le bureau compte, alors que son stock local ignore encore cette vente).
        sortie(['vente' => $nouvelles[0], 'stock_apres' => round((float) Product::findOrFail($p['produit'])->stock_qty, 2),
            'interblocages' => $interblocages]);

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

    // ── Ticket S-T12 : le même produit créé au web qu'au poste (fusion S-T5), par « Ajouter un Produit » ─────────────
    case 'produit-web':
        $p = json_decode($arguments[0] ?? '{}', true);
        $avant = Product::pluck('id')->all();
        $composant = web(App\Livewire\Stocks\AjouterProduit::class)
            ->set('name', $p['nom'])
            ->set('category_id', $p['categorie'])
            ->set('species_id', $p['espece'] ?? '')
            ->set('unit', $p['unite'])
            ->set('pricing_mode', 'fourchette')
            ->set('price_min', (float) $p['prix_min'])
            ->set('price_max', (float) $p['prix_max'])
            ->set('stock_qty', (float) ($p['stock'] ?? 0))
            ->call('save');
        $nouveaux = Product::whereNotIn('id', $avant)->pluck('id')->all();
        if (count($nouveaux) !== 1) {
            echec('Produit non créé au web : '.diagnostic($composant));
        }

        sortie(['produit' => $nouveaux[0]]);

    // ── Ticket S-T12 : inventaire au web (Gestion des Stocks, onglet Ajustement) ──────────────────────────────────────
    case 'inventaire-web':
        // `ecart` : ce que les rayons contiennent de plus (ou de moins) que le stock du serveur à cet instant.
        $p = json_decode($arguments[0] ?? '{}', true);
        $p['compte'] = round((float) Product::findOrFail($p['produit'])->stock_qty + (float) $p['ecart'], 2);
        $composant = web(App\Livewire\Stocks\GestionStocks::class)
            ->set('adjProductId', $p['produit'])
            ->set('adjPhysical', (float) $p['compte'])
            ->set('adjReason', $p['motif'] ?? 'Casse')
            ->call('validateAdjustment');
        $stock = round((float) Product::findOrFail($p['produit'])->stock_qty, 2);
        if ($stock !== round((float) $p['compte'], 2)) {
            echec("Inventaire web non appliqué (stock {$stock}) : ".diagnostic($composant));
        }

        sortie(['stock' => $stock, 'le' => now()->toIso8601String()]);

    // ── Ticket S-T12 : session refusée (CFG-1, S3) ────────────────────────────────────────────────────────────────
    case 'revoquer':
        $poste = $arguments[0] ?? '';
        web(App\Livewire\Parametres\PostesAppairage::class)->call('revoquer', $poste);
        $restants = DB::table('personal_access_tokens')->where('name', $poste)->count();
        if ($restants !== 0) {
            echec("Appairage du poste {$poste} non révoqué ({$restants} jeton(s)).");
        }

        sortie(['revoque' => $poste]);

    case 'desactiver':
    case 'reactiver':
        $compte = User::where('username', $arguments[0] ?? '')->firstOrFail();
        web(App\Livewire\Parametres\GestionUtilisateurs::class)
            ->call($commande === 'desactiver' ? 'archiveUser' : 'reactivateUser', $compte->id);
        $actif = (bool) $compte->fresh()->is_active;
        if ($actif !== ($commande === 'reactiver')) {
            echec("Compte {$compte->username} : {$commande} sans effet.");
        }

        sortie(['compte' => $compte->username, 'actif' => $actif, 'jetons' => $compte->tokens()->count()]);

    // ── Ticket S-T6 : demande de synchronisation d'un poste, et sa lecture par le poste ──────────────────────────────
    case 'demander':
        $poste = $arguments[0] ?? '';
        web(App\Livewire\Parametres\PostesAppairage::class)->call('demander', $poste);
        $demande = App\Models\DemandeSynchronisation::where('poste', $poste)->latest('demandee_le')->first();
        if ($demande === null) {
            echec("Demande de synchronisation du poste {$poste} non déposée.");
        }

        sortie(['demande' => $demande->id, 'le' => $demande->demandee_le->toIso8601String()]);

    case 'demande':
        $servie = App\Models\DemandeSynchronisationServie::where('demande_id', $arguments[0] ?? '')->first();

        sortie(['servie' => $servie !== null, 'le' => $servie?->servie_le]);

    // ── Ticket S-T12 : réinitialisation des données (15.50), par l'écran de Paramètres ──────────────────────────────
    case 'reinitialiser':
        $composant = web(App\Livewire\Parametres\ReinitialisationDonnees::class);
        if (! (bool) (App\Models\CompanySetting::first()?->demo_mode_enabled)) {
            $composant->call('basculerModeDemo');
        }
        $composant->set('confirmation', App\Livewire\Parametres\ReinitialisationDonnees::MOT_DE_CONFIRMATION)->call('reinitialiser');
        $marque = App\Models\CompanySetting::query()->value('data_reset_at');
        if ($marque === null) {
            echec('Réinitialisation non faite : '.diagnostic($composant));
        }

        sortie(['data_reset_at' => (string) $marque]);

    case 'etat-reinitialise':
        $restantes = [];
        $marque = App\Models\CompanySetting::query()->value('data_reset_at');
        foreach (ReinitialisationDonneesService::tablesTransactionnelles() as $table) {
            if (! Illuminate\Support\Facades\Schema::hasTable($table)) {
                continue;
            }
            $requete = DB::table($table);
            // Le journal de synchronisation (H3) consigne les synchronisations des postes APRÈS la réinitialisation :
            // ces lignes-là sont la trace de l'essai, pas une donnée ressuscitée. Celles d'avant doivent avoir disparu.
            if ($table === 'journal_synchronisation' && $marque !== null) {
                $requete->where('created_at', '<', $marque);
            }
            if (($n = $requete->count()) > 0) {
                $restantes[$table] = $n;
            }
        }

        sortie(['restantes' => $restantes, 'data_reset_at' => (string) App\Models\CompanySetting::query()->value('data_reset_at')]);

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
            // Ticket S-T12 — tout ce qui se synchronise.
            'products' => 'products', 'expenses' => 'expenses', 'supplier_payments' => 'supplier_payments',
            'supplier_refunds' => 'supplier_refunds', 'advance_imputations' => 'advance_imputations',
            'infirmary_records' => 'infirmary_records', 'veterinary_calendar_events' => 'veterinary_calendar_events',
            'livestock_reproduction_events' => 'livestock_reproduction_events', 'feed_types' => 'feed_types',
            'feed_ration_standards' => 'feed_ration_standards',
        ];
        $presence = [];
        foreach ($tables as $cle => $table) {
            foreach ($saisies[$cle] ?? [] as $id) {
                $idServeur = in_array($table, ['customers', 'suppliers', 'products'], true) ? ($fusion->idServeur($table, $id) ?? $id) : $id;
                $presence[$cle][$id] = DB::table($table)->where('id', $idServeur)->count();
            }
        }
        // Retours fournisseurs : une ligne par ligne d'achat, rattachées au lot du poste (`return_batch_id`) ; « présent
        // une fois » = le lot existe (ses lignes sont comptées à part, dans `retours`).
        $retours = [];
        foreach ($saisies['purchase_returns'] ?? [] as $id) {
            $n = DB::table('purchase_returns')->where('return_batch_id', $id)->count();
            $presence['purchase_returns'][$id] = $n > 0 ? 1 : 0;
            $retours[$id] = $n;
        }

        // Ticket S-T12 — l'état au serveur des lignes saisies aux postes dont l'essai compare les champs avec le poste
        // qui les a saisies (cycle de reproduction, infirmerie, calendrier, archivage d'un soin, barèmes d'élevage).
        $colonnes = [
            'livestock_reproduction_events' => ['status', 'palpation_date', 'mise_bas_date_actual', 'nes_vivants', 'nes_morts'],
            'infirmary_records' => ['status'],
            'veterinary_calendar_events' => ['status'],
            'veterinary_records' => ['is_active'],
            'feed_ration_standards' => ['ration_g_per_day', 'is_active'],
            'feed_types' => ['name', 'price_per_kg', 'is_active'],
        ];
        $lignes = [];
        foreach ($colonnes as $table => $cols) {
            foreach ($saisies[$table] ?? [] as $id) {
                $ligne = DB::table($table)->where('id', $id)->first($cols);
                $lignes[$table][$id] = $ligne === null ? null : array_map(
                    fn ($v) => is_string($v) && preg_match('/^\d{4}-\d{2}-\d{2}/', $v) ? substr($v, 0, 10) : $v,
                    (array) $ligne,
                );
            }
        }
        $lignes['company_settings'] = ['rappel_soins_jours' => App\Models\CompanySetting::query()->value('rappel_soins_jours')];

        // Dépenses : chacune comptabilisée UNE fois (une écriture `expense` active qui la désigne).
        $depenses = [];
        foreach ($saisies['expenses'] ?? [] as $id) {
            $depenses[$id] = DB::table('accounting_entries')->where('source_type', 'expense')->where('source_id', $id)
                ->where('is_active', true)->count();
        }

        // Avances saisies aux postes : `amount_used` = somme des imputations reçues (ni perdue, ni comptée deux fois).
        $avances = [];
        foreach ($saisies['customer_advances'] ?? [] as $id) {
            $a = DB::table('customer_advances')->where('id', $id)->first(['amount', 'amount_used']);
            $avances[$id] = $a === null ? null : [
                'montant' => round((float) $a->amount, 2),
                'utilise' => round((float) $a->amount_used, 2),
                'imputations' => round((float) DB::table('advance_imputations')->where('customer_advance_id', $id)->sum('amount'), 2),
            ];
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
        // Ticket S-T12 — produits : même clé naturelle (S-T5) parmi les fiches actives, dont une créée pendant l'essai.
        $produits = [];
        foreach (Product::where('is_active', true)->get(['id', 'name', 'category_id', 'unit', 'species_id']) as $produit) {
            $cle = $fusion->cleNaturelle('products', $produit->toArray());
            if ($cle !== null) {
                $produits[$cle][] = $produit->id;
            }
        }
        $doublons['produits_meme_cle'] = array_filter($produits, fn ($ids) => count($ids) > 1
            && array_diff($ids, array_keys($avant['stocks'])) !== []);

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

        // 6. Ticket S-T12 — les deux côtés de chaque flux ont bougé d'autant depuis l'instantané (au centime).
        $s0 = $avant['soldes'];
        $s1 = $apres['soldes'];
        $d = fn (array $a, array $b, string $k) => round(($b[$k] ?? 0) - ($a[$k] ?? 0), 2);
        $codes = array_unique(array_merge(array_keys($s0['tresorerie']), array_keys($s1['tresorerie'])));
        $tresorerie = [];
        foreach ($codes as $code) {
            $tresorerie[$code] = [
                'comptes' => $d($s0['tresorerie'], $s1['tresorerie'], $code),
                'classe5' => $d($s0['livre'], $s1['livre'], $code),
            ];
        }
        $concordance = [
            'tresorerie' => $tresorerie,
            // Solde débiteur du 411 = créances ; créditeur du 401 = dettes ; créditeur du 419 = avances ; débiteur du 409.
            'creances_clients' => ['metier' => round($s1['creances_clients'] - $s0['creances_clients'], 2), 'livre' => $d($s0['livre'], $s1['livre'], '411')],
            'dettes_fournisseurs' => ['metier' => round($s1['dettes_fournisseurs'] - $s0['dettes_fournisseurs'], 2), 'livre' => -$d($s0['livre'], $s1['livre'], '401')],
            'avances' => ['metier' => round($s1['avances'] - $s0['avances'], 2), 'livre' => -$d($s0['livre'], $s1['livre'], '419')],
            'creances_fournisseurs' => ['metier' => round($s1['creances_fournisseurs'] - $s0['creances_fournisseurs'], 2), 'livre' => $d($s0['livre'], $s1['livre'], '409')],
        ];

        sortie([
            'concordance' => $concordance,
            'depenses' => $depenses,
            'avances' => $avances,
            'retours' => $retours,
            'lignes' => $lignes,
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
