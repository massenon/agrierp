<?php

namespace App\Http\Controllers\Api;

use App\Actions\AdjustStockAction;
use App\Models\LivestockTransfer;
use App\Actions\TransferBetweenLotsAction;
use App\Actions\VerifySaleDateAction;
use App\Exceptions\SaleDateRefusedException;
use App\Actions\RecordPurchaseAction;
use App\Actions\SyncLotProductionStockAction;
use App\Actions\FlagSaleUnderWithdrawalAction;
use App\Actions\RecordEggProductionStockAction;
use App\Actions\RecordStockAdjustmentEntryAction;
use App\Actions\RecordSaleOnFicheElevageAction;
use App\Actions\RecordSaleAccountingEntryAction;
use App\Actions\CreditTreasuryForSaleAction;
use App\Http\Controllers\Controller;
use App\Services\AvoirClientService;
use App\Exceptions\ClosedFiscalYearException;
use App\Exceptions\NoOpenFiscalYearException;
use App\Models\Animal;
use App\Models\AttestationTemplate;
use App\Models\AuditLog;
use App\Models\LivestockSpecies;
use App\Models\Notification;
use App\Services\AttestationService;
use App\Services\EffectifParCategorieService;
use App\Services\FusionReferentielsService;
use App\Services\JournalSynchronisationService;
use App\Services\Mecef\FacturationMecefService;
use App\Services\TransactionRejouable;
use App\Services\LotRevenueService;
use App\Services\ProductCatalogService;
use Illuminate\Support\Arr;
use Illuminate\Support\Str;
use App\Models\FeedRationStandard;
use App\Models\LivestockDailyEntry;
use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\AdministrativeDocument;
use App\Models\ChartOfAccount;
use App\Models\CompanySetting;
use App\Models\ModuleConfig;
use App\Models\User;
use App\Models\FiscalYear;
use App\Models\ArchivedDocument;
use App\Models\AttendanceRecord;
use App\Models\Correspondence;
use App\Models\Employee;
use App\Models\Internship;
use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Models\CustomerReminder;
use App\Models\ElevageNumberingSetting;
use App\Models\FeedType;
use App\Models\Payable;
use App\Models\Purchase;
use App\Models\Role;
use App\Models\PurchaseOrder;
use App\Models\Supplier;
use App\Models\LivestockLot;
use App\Models\LivestockReproductionEvent;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Receivable;
use App\Models\Quote;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Actions\RecordVeterinaryCareAction;
use App\Models\ProphylaxisScheduleStandard;
use App\Models\VeterinaryRecord;
use App\Models\VeterinaryWithdrawalPeriod;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use App\Support\MessagesErreurFr;
use App\Support\MotifsRefusPush;
use App\Support\OrdreDesVerrous;
use Illuminate\Validation\ValidationException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Date;
use Illuminate\Contracts\Auth\Access\Authorizable;
use Illuminate\Support\Collection;
use Laravel\Sanctum\PersonalAccessToken;

/**
 * GAP CRITIQUE COMBLÉ — `POST /api/sync/push` et `GET /api/sync/pull`,
 * documentés depuis longtemps dans `LARAVEL_SYNC_FLUTTER.md`, jamais
 * construits avant ce ticket. Implémente réellement les règles de
 * résolution de conflit déjà documentées, différenciées par nature de
 * donnée — jamais un simple "dernier écrivain gagne" partout, ce
 * serait dangereux pour un ERP financier :
 *
 * | Donnée | Règle appliquée ici |
 * |---|---|
 * | Référentiels (produits, catégories) | Le serveur a toujours raison — `pull` seulement, `push` ignoré silencieusement (mais tracé) |
 * | Fiches élevage journalières | Dernier écrivain gagne (upsert par id) |
 * | Ventes POS | Jamais fusionnées — chaque vente hors-ligne insérée comme transaction indépendante, jamais de mise à jour d'une vente existante par push |
 * | Mouvements de stock | Jamais acceptés tels quels — réappliqués via `AdjustStockAction`, seul point d'entrée réel de toute mutation de stock (ticket 6.1), pour garantir un recalcul serveur complet |
 * | Clôture d'exercice | Jamais synchronisée — l'API ne l'accepte sous aucune forme, cohérent avec "bloqué explicitement côté Flutter si pas de connexion" déjà documenté |
 *
 * ⚠️ PORTÉE HONNÊTE DE CE TICKET : implémente le mécanisme réel et
 * DÉMONTRE chaque règle sur un jeu de tables représentatif
 * (référentiels : produits/catégories ; fiches élevage ; ventes ; stock)
 * plutôt que les ~59 tables du schéma complet — chantier qui dépasserait
 * largement un seul ticket. Étendre à une nouvelle table métier suit le
 * même patron que les blocs ci-dessous, pas une architecture à
 * réinventer.
 */
class SyncController extends Controller
{
    /**
     * Toutes les clés que `/sync/push` lit (tables écrivables ET référentiels ignorés) : chacune
     * doit être une liste ; sinon elle est écartée et signalée (ticket 15.26).
     */
    private const CLES_DE_PUSH = [
        'livestock_daily_entries', 'sales', 'stock_adjustments', 'veterinary_records', 'expenses',
        // Ticket BS1 — bandes créées, modifiées et archivées au poste.
        'livestock_lots',
        'livestock_reproduction_events', 'purchases', 'attendance_records', 'products', 'suppliers',
        'customers', 'mails', 'archived_documents', 'administrative_documents', 'supplier_payments',
        'purchase_returns', 'supplier_refunds', 'customer_advances', 'advance_imputations',
        'product_categories', 'receivables', 'customer_reminders', 'feed_types', 'elevage_numbering',
        'purchase_orders', 'payables', 'employees', 'internships', 'chart_of_accounts', 'fiscal_years',
        'accounting_entries', 'accounting_entry_lines', 'company_settings', 'modules_config', 'roles',
        'users', 'audit_logs', 'notifications', 'lot_revenues', 'animals', 'livestock_species',
        'attestation_templates', 'attestation_counts', 'livestock_transfers',
        // Ticket H8b — infirmerie et calendrier vétérinaire saisis au poste.
        'infirmary_records', 'veterinary_calendar_events',
        // Ticket H9b — barèmes d'élevage modifiables au poste.
        'feed_ration_standards', 'prophylaxis_schedule_standards',
        // Ticket U2 — objectifs de GMQ : référentiel en lecture seule au poste.
        'growth_standards',
        // Ticket U9 — grand livre des stocks : lecture seule au poste.
        'stock_movements',
        // Ticket DEV — devis (« Devis & Proforma ») saisis, avancés et archivés au poste.
        'quotes',
        // Ticket DEV3 — DEMANDES de conversion d'un devis accepté en facture (le serveur crée la facture).
        'quote_conversions',
        // Ticket U13 — paie réglée : lecture seule au poste (Recettes et Dépenses).
        'payslips',
        // Ticket AV1 — retours et avoirs clients saisis au poste (demande ; le serveur fait les effets).
        'credit_notes',
        // Ticket ARC2 — Corbeille : demandes de restauration / de suppression définitive (le serveur fait les effets).
        'corbeille_demandes',
    ];

    /** Recouvrement du curseur de tirage (voir `pull`). */
    public const HORIZON_TIRAGE_SECONDES = 5;

    /**
     * Ticket S-T4 — taille d'une page du tirage paginé, en LIGNES servies : une pièce compte pour elle-même plus
     * chacune de ses lignes (lignes de vente, d'achat, de retour, d'écriture), car elle ne se coupe jamais. Le poste
     * peut demander moins (`taille`), jamais plus que [TAILLE_PAGE_MAXIMUM].
     */
    public const TAILLE_PAGE = 1000;

    public const TAILLE_PAGE_MAXIMUM = 5000;

    /** Ticket S-T4 — `updated_at` absent (ligne écrite hors Eloquent) : rangée en tête de l'ordre des pages. */
    private const MAJ_NULLE = '1970-01-01 00:00:00';

    /**
     * 🔴→✅ TICKET S-T4 (méthode TATACORA) — TABLES QUE LE COMPTE LIT : la correspondance UNIQUE table tirée →
     * permission(s) de LECTURE, en face de [PERMISSION_PAR_TABLE] (permissions d'ÉCRITURE à l'envoi).
     *
     *  - `null` : table du FONCTIONNEMENT DE BASE, servie à tout compte ;
     *  - liste : servie si l'utilisateur a AU MOINS UNE de ces permissions (`$user->can()`, Spatie : la matrice des
     *    droits du web s'applique telle qu'elle est en base, pas telle que le seeder l'a créée).
     *
     * ⚠️⚠️ LE TABLEAU DE BORD EST OUVERT AUX QUATRE RÔLES (route web `auth` seul ; `dashboard.html` est dans les
     * quatre listes de `RBAC_PAGE_MAP`, recopiée par `PermissionsPoste`) et il lit les ventes et leurs lignes, les
     * achats et leurs lignes, les clients, créances et dettes, les bandes, leurs fiches et les cycles de
     * reproduction, les produits et catégories, la trésorerie et les exercices : ces tables sont donc de BASE, même
     * pour l'animalier ou le comptable. Les retirer viderait les cartes du tableau de bord sans rien dire. De même :
     * `users` (Mon Profil), `notifications` (la cloche, tous rôles), `audit_logs` (servi à tous, mais VIDE sans
     * `manage-users` — ticket S3, inchangé : une liste vide, et non une clé absente, purge un poste partagé),
     * `roles`, `company_settings` et `modules_config` (petits référentiels lus partout).
     *
     * ⚠️ UNE PIÈCE ET SES LIGNES ONT LA MÊME PERMISSION (`sales` / `sale_lines`, `purchases` / `purchase_lines` /
     * `purchase_returns`, `accounting_entries` / `accounting_entry_lines` / `accounting_entry_ids`) : elles
     * descendent ensemble ou pas du tout (U4, U8, F0.84).
     *
     * ⚠️ LISTE CROISÉE AVEC LES ÉCRANS DU POSTE : `agrierp_flutter/test/perimetre_tirage_test.dart` lit CE tableau
     * (une entrée par ligne, sous cette forme exacte) et vérifie, pour chacun des quatre rôles, que toute table lue
     * par un écran que le rôle ouvre lui est servie. L'ordre est celui des clés de la réponse.
     *
     * ⚠️ PORTÉE : ne s'applique qu'au tirage PAGINÉ (`page`), celui des postes à jour. Un poste antérieur, qui
     * n'envoie pas `page`, reçoit la réponse complète d'avant S-T4 : il ne saurait pas qu'un changement de rôle lui
     * impose une resynchronisation (voir `tables_servies`).
     *
     * @var array<string, array<int, string>|null>
     */
    public const PERMISSIONS_DE_TIRAGE = [
        'products' => null,
        'product_categories' => null,
        'livestock_lots' => null,
        'livestock_daily_entries' => null,
        'livestock_transfers' => ['view-elevage'],
        'feed_ration_standards' => ['view-elevage', 'view-ventes'],
        'growth_standards' => ['view-elevage'],
        'veterinary_withdrawal_periods' => ['view-elevage', 'view-ventes'],
        'prophylaxis_schedule_standards' => ['view-elevage'],
        'veterinary_records' => ['view-elevage'],
        'infirmary_records' => ['view-elevage'],
        'veterinary_calendar_events' => ['view-elevage'],
        'livestock_reproduction_events' => null,
        'customers' => null,
        'receivables' => null,
        'customer_advances' => ['view-ventes'],
        'customer_reminders' => ['view-ventes'],
        'feed_types' => ['view-elevage'],
        'elevage_numbering' => ['view-elevage'],
        'suppliers' => ['view-achats', 'view-rapports'],
        'purchases' => null,
        'purchase_lines' => null,
        'purchase_returns' => null,
        'supplier_credits' => ['view-achats'],
        'purchase_orders' => ['view-achats'],
        'payables' => null,
        'employees' => ['view-rh'],
        'internships' => ['view-rh'],
        'attendance_records' => ['view-rh'],
        'mails' => ['view-administration'],
        'administrative_documents' => ['view-administration'],
        'archived_documents' => ['view-administration'],
        // Ticket DEP3 — les comptes de CHARGE (classe 6) de la modale « Nouvelle Dépense » : l'écran est celui de
        // `view-achats`, qui n'a pas le journal. Le plan comptable n'a rien de confidentiel (numéros et intitulés).
        'chart_of_accounts' => ['view-comptabilite', 'view-achats'],
        // Ticket DEP3 — centres de coût (filières) de l'en-tête d'une dépense : petit référentiel, lecture seule.
        'cost_centers' => ['view-achats', 'view-comptabilite'],
        'fiscal_years' => null,
        'accounting_entries' => ['view-comptabilite'],
        'accounting_entry_lines' => ['view-comptabilite'],
        'accounting_entry_ids' => ['view-comptabilite'],
        'company_settings' => null,
        'modules_config' => null,
        'roles' => null,
        'users' => null,
        'audit_logs' => null,
        'notifications' => null,
        'lot_revenues' => ['view-elevage'],
        'animals' => ['view-elevage'],
        'livestock_species' => ['view-elevage', 'view-stocks'],
        'attestation_templates' => ['view-rh'],
        'attestation_counts' => ['view-rh'],
        'sales' => null,
        'sale_lines' => null,
        // Ticket DEV — DEVIS : aux comptes qui ouvrent « Ventes & Devis » (`view-ventes`, la permission de la route du
        // hub), comme le web leur montre l'onglet « Devis Prestations ». Archivés compris (`is_active`).
        'quotes' => ['view-ventes'],
        // Ticket AV1 — « Retours et Avoirs » (hub Ventes & Devis, `view-ventes`, comme `customer_advances`).
        'credit_notes' => ['view-ventes'],
        'stock_movements' => ['view-elevage', 'view-stocks', 'view-rapports'],
        'treasury_accounts' => null,
        'expense_categories' => ['view-achats'],
        // Ticket U13 — DÉPENSES : de BASE, comme les achats. Le Tableau de bord (ouvert aux quatre rôles) les liste au
        // web (« Dépenses récentes » : `Expense::where('is_active', true)->latest('expense_date')`) ; le rapport
        // « Recettes et Dépenses » les compte. Libellé, compte de charge, montant, date, compte payeur, archivage :
        // rien qu'un compte connecté ne voie déjà au web.
        'expenses' => null,
        // Ticket DEP3 — les LIGNES d'une dépense voyagent avec elle (même permission, même curseur : jamais une ligne
        // sans son en-tête).
        'expense_lines' => null,
        // Ticket U13 — PAIE RÉGLÉE : aux seuls comptes qui lisent les RAPPORTS (`view-rapports`, la permission de la
        // route du hub où « Recettes et Dépenses » l'affiche). ⚠️ Protection S3 des salaires : ni `view-rh` (le poste
        // n'affiche aucun bulletin : les cartes de la paie y sont des « — »), ni base ; et seulement ce que le rapport
        // affiche au web à ces mêmes comptes (instant du règlement, nom de l'employé, NET versé) — jamais le brut, les
        // retenues, les charges patronales ni la période (voir [famillesPaginees]).
        'payslips' => ['view-rapports'],
        // Ticket ARC2 — CORBEILLE : l'instantané des éléments archivés, avec ce que le serveur permet d'en faire. Aux
        // seuls comptes qui gèrent les Paramètres (l'administrateur) : la liste agrège les archives de TOUS les modules.
        'corbeille' => ['manage-parametres'],
    ];

    /**
     * Ticket S-T4 — tables servies à ce compte, dans l'ordre de la réponse (voir [PERMISSIONS_DE_TIRAGE]).
     *
     * @return array<int, string>
     */
    public static function tablesServies(?Authorizable $utilisateur): array
    {
        $servies = [];
        foreach (self::PERMISSIONS_DE_TIRAGE as $table => $permissions) {
            if ($permissions === null
                || ($utilisateur !== null && collect($permissions)->contains(fn (string $p) => $utilisateur->can($p)))) {
                $servies[] = $table;
            }
        }

        return $servies;
    }

    /**
     * GET /api/sync/pull?since=2026-08-11T00:00:00Z
     * Renvoie tout ce qui a changé côté serveur depuis `since`, groupé
     * par table. `since` absent ou vide = synchronisation initiale
     * complète (première connexion d'un appareil).
     *
     * 🔴→✅ TICKET S-T4 (méthode TATACORA) — TIRAGE PAGINÉ ET LIMITÉ AUX TABLES QUE LE COMPTE LIT. Un poste resté
     * longtemps hors ligne recevait tout en UNE réponse (délai de réception de 30 s du client, mémoire). Avec `page`
     * (`page=1`, puis `page=n&curseur_page=<jeton rendu par la page précédente>`, `taille` facultative) :
     *
     *  - la PAGE 1 porte toutes les tables NON paginées (référentiels, tables servies en entier : leur sémantique de
     *    remplacement complet est gardée, elles ne se découpent jamais), `data_reset_at` et `tables_servies` ;
     *  - les tables d'HISTORIQUE ([famillesPaginees] : fiches, transferts, soins, infirmerie, calendrier, cycles,
     *    achats + lignes + retours, ventes + lignes, dépenses et paie (U13), grand livre des stocks, journal
     *    comptable + lignes) se découpent
     *    PAR PIÈCE, au curseur composite (`updated_at`, `id`) : une pièce descend avec TOUTES ses lignes (U4, U8 :
     *    l'absorbeur strict du poste refuserait une ligne d'une pièce non servie) ;
     *  - `server_time` (instant du DÉBUT de la page 1, reculé de l'horizon) et `accounting_entry_ids` ne viennent
     *    qu'à la DERNIÈRE page (`page_suivante: null`). Le poste n'avance son curseur qu'après avoir absorbé toutes les
     *    pages ; un échec au milieu le fait repartir du curseur précédent (rien de perdu ; ce qui revient est remplacé
     *    par identifiant) ;
     *  - les pièces servies sont celles d'AVANT la page 1 (`updated_at` < son début, sauf le journal : voir
     *    [famillesPaginees]) : ce qui s'écrit pendant le tirage descend au suivant, jamais avec un produit ou une
     *    bande que la page 1 n'a pas pu servir ;
     *  - seules les tables que le compte lit sont servies ([PERMISSIONS_DE_TIRAGE]), et `tables_servies` les nomme à
     *    chaque page : le poste compare à celles de son dernier tirage et repart SANS `since` si une table s'ajoute
     *    (changement de rôle, de droits ou d'utilisateur) — sinon l'historique de cette table antérieur au curseur
     *    ne lui parviendrait jamais.
     *
     * ⚠️ COMPATIBILITÉ : sans `page`, la réponse est celle d'avant S-T4, complète et non filtrée (poste antérieur).
     */
    public function pull(Request $request): JsonResponse
    {
        $request->validate([
            'since' => ['nullable', 'date'],
            'page' => ['nullable', 'integer', 'min:1'],
            'curseur_page' => ['nullable', 'string'],
            'taille' => ['nullable', 'integer', 'min:1', 'max:'.self::TAILLE_PAGE_MAXIMUM],
        ]);

        // Ticket S-T2 — le poste ne l'envoie pas au tirage aujourd'hui ; s'il l'envoie, il doit être celui du jeton.
        if ($refus = $this->refusPosteDifferentDuJeton($request)) {
            return $refus;
        }

        if ($request->filled('page') || $request->filled('curseur_page')) {
            return $this->tiragePagine($request);
        }

        $since = $request->filled('since') ? $this->curseurDuPoste((string) $request->input('since')) : null;

        // 🔴→✅ CURSEUR PRIS AVANT LES REQUÊTES, AVEC UN RECOUVREMENT. `server_time` était calculé APRÈS les quelque
        // 900 lignes de requêtes ci-dessous : une ligne écrite au web PENDANT le tirage (après la lecture de sa table)
        // portait un `updated_at` antérieur au curseur rendu — ni servie par ce tirage, ni par le suivant, perdue pour
        // le poste sans aucune erreur. Le curseur est désormais l'instant du DÉBUT du tirage, reculé de
        // [HORIZON_TIRAGE_SECONDES] : une écriture dont la transaction se valide juste après (ou datée à la seconde
        // près) est resservie au tirage suivant. Resservir est sans risque : les absorbeurs du poste font des
        // insertions-ou-mises-à-jour et ne touchent jamais une saisie locale en attente.
        $curseur = now()->subSeconds(self::HORIZON_TIRAGE_SECONDES);

        $reponse = [
            'server_time' => $curseur->toIso8601String(),
            // Ticket 15.50 — instant de la dernière réinitialisation des données (null : jamais). Un poste qui ne le
            // connaît pas purge ses données d'activité avant tout envoi.
            'data_reset_at' => $this->instantDeReinitialisation(),
        ];
        // Ticket SW-1 — « resynchronisation demandée » (clé absente sans drapeau).
        $reponse += $this->drapeauDeResynchronisation($request);
        foreach ($this->tablesNonPaginees($request, $since) as $cle => $calcul) {
            $reponse[$cle] = $calcul();
        }
        foreach ($this->famillesPaginees($since) as $famille) {
            $requete = $famille['requete']();
            if (isset($famille['historique'])) {
                $requete = $famille['historique']($requete);
            }
            $reponse += $this->servirPieces($famille, $requete->get());
        }
        $reponse['accounting_entry_ids'] = $this->idsDesEcrituresActives();
        $reponse = $this->dansLOrdreDuTirage($reponse);

        // Ticket H3 — chaque tirage est journalisé par poste (modale « Synchronisation » du web).
        app(JournalSynchronisationService::class)->tirage($request, $reponse);

        return response()->json($reponse);
    }

    /**
     * 🔴→✅ Ticket S-T12 (trouvé par l'essai à plusieurs postes) — LE CURSEUR DU POSTE EST RAMENÉ À L'HEURE DU SERVEUR.
     *
     * Le poste renvoie `since` en UTC (`2026-10-19T17:39:25.000Z`, l'instant que `server_time` lui a donné). Laissé tel
     * quel, Eloquent le comparait à `updated_at` — enregistré à l'heure MURALE du serveur (Africa/Porto-Novo, UTC+1) —
     * comme une heure murale : le curseur reculait d'une heure, et chaque tirage « incrémental » resservait toute la
     * dernière heure d'activité. Mesuré sur le jeu de démonstration (saisi dans l'heure) : 6 pages de 1 000 lignes
     * pour un tirage censé n'apporter que la minute écoulée, chaque page à refaire depuis la première à la moindre
     * coupure. Un curseur envoyé avec un décalage À L'EST du serveur aurait, lui, fait sauter des lignes. L'instant est
     * donc converti dans le fuseau de l'application avant toute comparaison (même règle que `counted_at`, S-T10).
     */
    private function curseurDuPoste(string $brut): Carbon
    {
        return Date::parse($brut)->setTimezone(config('app.timezone'));
    }

    /**
     * Ticket S-T4 — une page du tirage paginé (voir `pull`).
     */
    private function tiragePagine(Request $request): JsonResponse
    {
        $etat = $this->etatDePage($request);
        if ($etat instanceof JsonResponse) {
            return $etat;
        }

        $premiere = $etat === null;
        if ($premiere) {
            // Même curseur que le tirage complet (début, reculé de l'horizon), pris AVANT la première requête et
            // rendu à la dernière page seulement. `debut` borne les pièces servies par toutes les pages.
            $debut = now();
            $etat = [
                'utilisateur' => (string) $request->user()?->getAuthIdentifier(),
                'debut' => $debut->format('Y-m-d H:i:s'),
                'curseur' => $debut->copy()->subSeconds(self::HORIZON_TIRAGE_SECONDES)->toIso8601String(),
                'since' => $request->filled('since') ? (string) $request->input('since') : null,
                'famille' => 0,
                'apres' => null,
                'recus' => 0,
            ];
        }

        // `since` est celui de la PAGE 1, porté par le jeton : toutes les pages d'un tirage lisent le même.
        $since = $etat['since'] !== null ? $this->curseurDuPoste($etat['since']) : null;
        $servies = self::tablesServies($request->user());

        $reponse = ['page' => (int) $request->input('page', 1), 'tables_servies' => $servies];

        if ($premiere) {
            $reponse['data_reset_at'] = $this->instantDeReinitialisation();
            $reponse += $this->drapeauDeResynchronisation($request);
            foreach ($this->tablesNonPaginees($request, $since) as $cle => $calcul) {
                if (in_array($cle, $servies, true)) {
                    $reponse[$cle] = $calcul();
                }
            }
        }

        $familles = $this->famillesPaginees($since);
        $budget = (int) $request->input('taille', self::TAILLE_PAGE);
        $poidsPage = 0;
        $suite = null;
        for ($i = $etat['famille']; $i < count($familles); $i++) {
            $famille = $familles[$i];
            if (! in_array($famille['cle'], $servies, true)) {
                continue;
            }
            $apres = $i === $etat['famille'] ? $etat['apres'] : null;
            if ($budget <= 0) {
                $suite = [$i, $apres];
                break;
            }

            [$servi, $poids, $reste, $position] = $this->pageDeFamille($famille, $apres, $budget, $etat['debut'], $poidsPage === 0);
            $reponse += $servi;
            $budget -= $poids;
            $poidsPage += $poids;
            if ($reste) {
                $suite = [$i, $position];
                break;
            }
        }

        // Chaque page porte TOUTES les clés paginées du périmètre (liste vide si elle n'en sert rien) : une clé ABSENTE
        // veut dire « table non servie à ce compte », jamais « rien sur cette page ».
        foreach ($familles as $famille) {
            if (in_array($famille['cle'], $servies, true)) {
                $reponse[$famille['cle']] ??= collect();
                foreach (array_keys($famille['lignes'] ?? []) as $cle) {
                    $reponse[$cle] ??= collect();
                }
            }
        }

        $journal = app(JournalSynchronisationService::class);
        if ($suite === null) {
            // DERNIÈRE PAGE : le journal comptable est complet au poste, la liste des écritures actives peut le
            // corriger (F0.84) ; le curseur est enfin rendu.
            if (in_array('accounting_entry_ids', $servies, true)) {
                $reponse['accounting_entry_ids'] = $this->idsDesEcrituresActives();
            }
            $reponse['server_time'] = $etat['curseur'];
            $reponse['page_suivante'] = null;
            $reponse = $this->dansLOrdreDuTirage($reponse);
            // Ticket H3 — UNE ligne de journal par tirage, toutes pages comptées (pas une par page).
            $journal->tirage($request, $reponse, $etat['recus']);
        } else {
            $reponse['page_suivante'] = Crypt::encryptString(json_encode([
                ...$etat,
                'famille' => $suite[0],
                'apres' => $suite[1],
                'recus' => $etat['recus'] + $journal->compter($reponse),
            ], JSON_THROW_ON_ERROR));
            $reponse = $this->dansLOrdreDuTirage($reponse);
        }

        return response()->json($reponse);
    }

    /**
     * Ticket S-T4 — état porté par `curseur_page` (chiffré par la clé de l'application : le poste ne le lit ni ne
     * le fabrique). `null` : page 1. Jeton illisible, d'un autre compte ou mal formé → 422, et le poste reprend
     * son tirage depuis le début.
     *
     * @return array<string, mixed>|JsonResponse|null
     */
    private function etatDePage(Request $request): array|JsonResponse|null
    {
        if (! $request->filled('curseur_page')) {
            return null;
        }

        try {
            $etat = json_decode(Crypt::decryptString((string) $request->input('curseur_page')), true, 8, JSON_THROW_ON_ERROR);
        } catch (\Throwable) {
            $etat = null;
        }

        $apres = $etat['apres'] ?? null;
        $valide = is_array($etat)
            && ($etat['utilisateur'] ?? null) === (string) $request->user()?->getAuthIdentifier()
            && is_string($etat['debut'] ?? null)
            && is_string($etat['curseur'] ?? null)
            && (! isset($etat['since']) || is_string($etat['since']))
            && is_int($etat['famille'] ?? null)
            && is_int($etat['recus'] ?? null)
            && ($apres === null || (is_array($apres) && count($apres) === 2
                && is_string($apres[0] ?? null) && is_string($apres[1] ?? null)));

        if (! $valide) {
            return response()->json([
                'message' => 'Page de tirage illisible : la synchronisation doit reprendre depuis le début.',
            ], 422);
        }

        $etat['since'] ??= null;

        return $etat;
    }

    /**
     * Ticket S-T4 — une tranche d'une famille paginée : au plus `$budget` lignes (pièces + leurs lignes), JAMAIS une
     * pièce coupée de ses lignes. Une page VIDE ([$pageVide]) prend toujours sa première pièce, même si ses lignes
     * dépassent le budget (sinon elle ne descendrait jamais) ; une page déjà entamée la laisse à la suivante.
     *
     * Ordre et curseur de page : (`updated_at`, `id`) de la PIÈCE ; `updated_at` absent est rangé en tête
     * ([MAJ_NULLE]). Une pièce modifiée pendant le tirage passe après le début de la page 1 : elle sort de ce tirage
     * (borne `debut`) et descend au suivant (son `updated_at` dépasse le curseur rendu).
     *
     * @param  array<string, mixed>  $famille
     * @param  array{0: string, 1: string}|null  $apres
     * @return array{0: array<string, Collection>, 1: int, 2: bool, 3: array{0: string, 1: string}|null}  pièces et
     *                                lignes servies, leur poids, s'il en reste, position de la dernière servie
     */
    private function pageDeFamille(array $famille, ?array $apres, int $budget, string $debut, bool $pageVide): array
    {
        $requete = $famille['requete']();
        $modele = $requete->getModel();
        $maj = $modele->qualifyColumn('updated_at');
        $id = $modele->getQualifiedKeyName();
        $ordre = "COALESCE({$maj}, '".self::MAJ_NULLE."')";

        if (! ($famille['sansBorne'] ?? false)) {
            $requete->where(fn ($q) => $q->whereNull($maj)->orWhere($maj, '<', $debut));
        }
        if ($apres !== null) {
            [$majApres, $idApres] = $apres;
            $requete->where(fn ($q) => $q->whereRaw("{$ordre} > ?", [$majApres])
                ->orWhere(fn ($e) => $e->whereRaw("{$ordre} = ?", [$majApres])->where($id, '>', $idApres)));
        }

        $lot = $requete->orderByRaw("{$ordre} asc")->orderBy($id)->limit($budget + 1)->get()->values();
        $reste = $lot->count() > $budget;
        $lot = $lot->take($budget)->values();

        $servi = $this->servirPieces($famille, $lot);

        $lignesParPiece = [];
        foreach ($famille['lignes'] ?? [] as $cle => [$cleDePiece]) {
            foreach ($servi[$cle] as $ligne) {
                $piece = (string) data_get($ligne, $cleDePiece);
                $lignesParPiece[$piece] = ($lignesParPiece[$piece] ?? 0) + 1;
            }
        }

        $gardees = 0;
        $poids = 0;
        foreach ($lot as $piece) {
            $poidsPiece = 1 + ($lignesParPiece[(string) $piece->getKey()] ?? 0);
            if (($gardees > 0 || ! $pageVide) && $poids + $poidsPiece > $budget) {
                $reste = true;
                break;
            }
            $gardees++;
            $poids += $poidsPiece;
        }

        if ($gardees < $lot->count()) {
            $lot = $lot->take($gardees)->values();
            $gardes = $lot->map(fn ($piece) => (string) $piece->getKey())->flip();
            $servi[$famille['cle']] = $servi[$famille['cle']]->take($gardees)->values();
            foreach ($famille['lignes'] ?? [] as $cle => [$cleDePiece]) {
                $servi[$cle] = $servi[$cle]
                    ->filter(fn ($ligne) => $gardes->has((string) data_get($ligne, $cleDePiece)))
                    ->values();
            }
        }

        $derniere = $lot->last();
        $position = $derniere === null
            ? $apres
            : [(string) ($derniere->getRawOriginal('updated_at') ?? self::MAJ_NULLE), (string) $derniere->getKey()];

        return [$servi, $poids, $reste, $position];
    }

    /**
     * Ticket S-T4 — une famille paginée servie : ses pièces (sérialisées par `enJson` si elle en a un) et, pour
     * chaque clé de lignes, TOUTES les lignes de ces pièces, et d'elles seules.
     *
     * @param  array<string, mixed>  $famille
     * @return array<string, Collection>
     */
    private function servirPieces(array $famille, Collection $pieces): array
    {
        $servies = isset($famille['enJson']) ? $pieces->map($famille['enJson']) : $pieces;
        $reponse = [$famille['cle'] => $servies];
        foreach ($famille['lignes'] ?? [] as $cle => [, $lire]) {
            $reponse[$cle] = $lire($servies->pluck('id'));
        }

        return $reponse;
    }

    /**
     * Ticket S-T4 — clés de la réponse dans l'ordre d'avant S-T4 (celui de [PERMISSIONS_DE_TIRAGE]), précédées des
     * clés de service et suivies de `page_suivante`.
     *
     * @param  array<string, mixed>  $reponse
     * @return array<string, mixed>
     */
    private function dansLOrdreDuTirage(array $reponse): array
    {
        $ordre = ['page', 'server_time', 'data_reset_at', 'resynchronisation_demandee_le', 'tables_servies', ...array_keys(self::PERMISSIONS_DE_TIRAGE)];
        $ordonnee = [];
        foreach ($ordre as $cle) {
            if (array_key_exists($cle, $reponse)) {
                $ordonnee[$cle] = $reponse[$cle];
            }
        }

        return $ordonnee + $reponse;
    }

    /**
     * Ticket SW-1 — « RESYNCHRONISATION DEMANDÉE » : si l'administrateur a cliqué « Renvoyer vers ce poste », le tirage
     * porte l'instant de la demande (`resynchronisation_demandee_le`, ISO 8601). Clé ABSENTE sinon : un poste antérieur
     * l'ignore, un poste à jour repart d'un tirage complet puis acquitte (`POST /api/sync/resynchronisation/acquittement`).
     *
     * @return array<string, string>
     */
    private function drapeauDeResynchronisation(Request $request): array
    {
        $poste = \App\Services\ResynchronisationPostesService::nomDuPoste($request);
        if ($poste === null) {
            return [];
        }

        $le = app(\App\Services\ResynchronisationPostesService::class)->drapeau($poste);

        return $le === null ? [] : ['resynchronisation_demandee_le' => $le->toIso8601String()];
    }

    /** Ticket 15.50 — instant de la dernière réinitialisation des données (null : jamais). */
    private function instantDeReinitialisation(): ?string
    {
        return CompanySetting::query()->first()?->data_reset_at?->toIso8601String();
    }

    /**
     * 🔴→✅ TICKET 15.28 — LE POSTE DOIT POUVOIR RETIRER UNE ECRITURE.
     *
     * ⚠️⚠️ Le tirage ne sert que les ecritures ACTIVES modifiees depuis `since` : une ecriture ARCHIVEE (ou
     * supprimee physiquement par une reinitialisation / une restauration de sauvegarde) en SORT, et le poste, qui
     * fusionne sans jamais rien supprimer, la gardait pour toujours — comptee par son Journal, son Grand Livre et sa
     * Balance, sans aucune erreur. Contrat : `accounting_entry_ids` = identifiants de TOUTES les ecritures actives,
     * SANS filtre `since` (516 UUID, ~20 Ko). Le poste retire ce qui n'y figure plus. Ne depend d'aucun tirage
     * complet : un tirage incremental suffit.
     *
     * ⚠️ Le contrat sur les LIGNES : une ecriture servie arrive avec TOUTES ses lignes courantes (`updateManual`
     * supprime et recree les lignes, nouveaux ids) ; le poste remplace les lignes de cette ecriture par celles-la.
     *
     * Ticket S-T4 : au tirage paginé, la liste vient à la DERNIÈRE page seulement, quand toutes les écritures servies
     * sont absorbées.
     */
    private function idsDesEcrituresActives(): Collection
    {
        return AccountingEntry::query()
            ->where('is_active', true)
            ->orderBy('id')
            ->pluck('id')
            ->values();
    }

    /**
     * Tables NON paginées, dans l'ordre de la réponse : chacune est calculée seulement si elle est servie (closure).
     * Référentiels et tables servies EN ENTIER (remplacement complet au poste) : elles ne se découpent jamais, et
     * descendent toutes à la page 1 du tirage paginé (ticket S-T4).
     *
     * @return array<string, \Closure>
     */
    private function tablesNonPaginees(Request $request, ?Carbon $since): array
    {
        return [
            'products' => fn () => Product::query()->when($since, fn ($q) => $q->where('updated_at', '>', $since))->get(),
            'product_categories' => fn () => ProductCategory::query()->when($since, fn ($q) => $q->where('updated_at', '>', $since))->get(),
            // ⚠️ TICKET F0.14 — LE CODE ESPÈCE ACCOMPAGNE LA BANDE. Le poste n'a
            // pas de table des espèces : sans ce champ, il ne peut pas appliquer
            // le garde-fou « aviculture + stade ponte » qui empêche une ponte
            // d'escargots d'entrer au stock d'œufs de table (ticket 14.59). Il
            // devrait deviner à partir du seul stade — et se tromper.
            'livestock_lots' => fn () => LivestockLot::with('species')
                ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
                ->get()
                ->map(function (LivestockLot $lot) {
                    $ligne = $lot->toArray();
                    unset($ligne['species']);
                    $ligne['species_code'] = $lot->species?->code;

                    return $ligne;
                }),

            // 🔴→✅ TICKET 14.52 — LES RATIONS NORMATIVES DESCENDENT ENFIN.
            //
            // `feed_ration_standards` est un référentiel ÉDITABLE (écran
            // Paramètres > Élevage) : la ferme peut corriger une ration. Il
            // n'était pourtant pas servi par ce point d'entrée, ce qui ne
            // laissait au client Flutter que deux options, toutes deux
            // mauvaises — coder les grammages en dur et diverger en silence le
            // jour d'une correction, ou renoncer au calcul de provende.
            //
            // ⚠️ PAS DE FILTRE `since` ICI. La table compte une dizaine de
            // lignes et sert de base à un calcul affiché : un appareil qui
            // n'aurait jamais tiré depuis une modification garderait des
            // grammages périmés sans le savoir. Le coût d'un envoi complet à
            // chaque tirage est négligeable devant ce risque.
            // ⚠️ Ticket 14.55 — une ration ARCHIVÉE ne descend plus au poste. Le
            // référentiel y étant remplacé à chaque tirage, elle en disparaît donc
            // proprement, tout en restant restaurable côté serveur.
            'feed_ration_standards' => fn () => FeedRationStandard::where('is_active', true)
                ->orderBy('species_code')->orderBy('stage_label')->get(),

            // Ticket U2 (décision D-U2 du 19/10/2026) — OBJECTIFS DE GMQ : une seule source, `growth_standards`, au web ET
            // au poste (le poste et le Dashboard Élevage web portaient des constantes). Référentiel en lecture seule,
            // servi COMPLET à chaque tirage (une dizaine de lignes) : comme les rations, un poste resté hors ligne ne doit
            // pas garder un objectif périmé. Le poste remplace l'ensemble.
            'growth_standards' => fn () => \App\Models\GrowthStandard::query()
                ->orderBy('species_code')->orderBy('stage_label')
                ->get(['id', 'species_code', 'stage_label', 'gmq_min_g_per_day', 'gmq_max_g_per_day']),

            // 🔴→✅ TICKET 14.53 — LA RÉMANENCE VÉTÉRINAIRE DESCEND AU POSTE.
            //
            // ⚠️ C'EST UN BLOCAGE DE SANTÉ PUBLIQUE, PAS UN CONFORT. La caisse web
            // REFUSE une vente issue d'une bande sous rémanence (délai d'attente
            // après traitement) : vendre cette viande exposerait le consommateur à
            // des résidus d'antibiotiques. Le poste Desktop, lui, encaisse HORS
            // LIGNE — sans ces périodes, il n'avait aucun moyen de connaître
            // l'interdiction et l'aurait donc laissée passer.
            //
            // Servies SANS filtre `since`, pour la même raison que les rations :
            // un poste qui n'aurait rien tiré depuis un traitement récent ignorerait
            // le blocage le plus important.
            'veterinary_withdrawal_periods' => fn () => VeterinaryWithdrawalPeriod::query()
                ->whereDate('end_date', '>=', now()->toDateString())
                ->orderBy('end_date')
                ->get(),

            // 🔴→✅ TICKET 14.54 — LE CALENDRIER PROPHYLACTIQUE ET LE REGISTRE
            // DESCENDENT AU POSTE. Sans eux, la fiche d'élevage Desktop ne pouvait
            // afficher ni les traitements PRÉVUS du jour ni ceux déjà administrés :
            // les montrer vides aurait laissé croire à une absence de soin à faire.
            //
            // ⚠️ Le calendrier est servi SANS filtre `since` — une dizaine de
            // lignes qui pilotent un affichage sanitaire, et un poste resté hors
            // ligne depuis une correction proposerait sinon un protocole périmé.
            'prophylaxis_schedule_standards' => fn () => ProphylaxisScheduleStandard::where('is_active', true)
                ->orderBy('species_code')
                ->orderBy('period_label')
                ->get(),

            // 🔴→✅ TICKET 14.75 — LE FICHIER CLIENTS ET LES CREANCES DESCENDENT.
            //
            // ⚠️⚠️ TROIS TABLES REELLES, RIEN AU POSTE. `customers` (10 lignes),
            // `receivables` (51) et `customer_advances` (4) existent depuis les
            // premiers sprints ; aucune ne figurait dans la charge du tirage.
            // Consequences accumulees sur les ecrans deja livres :
            //   • la caisse ne peut nommer aucun client — `sales.customer_id`
            //     part rempli ou vide, jamais choisi ;
            //   • l'historique des ventes affiche « Client non synchronise » ;
            //   • « Encours Creances » est un tiret sur le Tableau de Bord ET sur
            //     l'historique des ventes ;
            //   • tout le hub « Clients et Creances » etait impossible a batir.
            //
            // ⚠️ `customers` S'ECRIT AU POSTE DEPUIS 15.18 (/sync/push, `pushCustomers`),
            // et descend desormais AVEC son e-mail. Les creances et les relances restent
            // servies en lecture seule : une creance se solde par un encaissement ou une
            // imputation d'avance, jamais par une edition.
            //
            // ⚠️ `customer_advances` S'ECRIT AU POSTE DEPUIS 15.19 (`pushCustomerAdvances`), avec ses
            // imputations (`advance_imputations`). Le tirage sert toutes les colonnes de l'avance,
            // dont `treasury_account_id`, `payment_mode`, `motif` et `device_id`.
            //
            // ⚠️ LE TIRAGE EST INCREMENTAL (`since`) et SANS FILTRE `is_active` : un client
            // archive descend avec `is_active = false`. Le poste FUSIONNE par identifiant ;
            // l'ancien « tout effacer puis reinserer » ne gardait que le delta (F0.72).
            'customers' => fn () => Customer::query()
                ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
                ->orderBy('name')
                ->get(['id', 'name', 'phone', 'email', 'city', 'credit_limit', 'is_active']),

            // ⚠️ SANS FILTRE `since` POUR CE QUI RESTE DU. Une facture echue il y a
            // trois mois n'a plus bouge depuis : un tirage incremental la
            // manquerait, et c'est precisement celle qu'il faut relancer. Meme
            // raisonnement que les remanences et les cycles en cours.
            'receivables' => fn () => Receivable::query()
                ->where(function ($q) use ($since) {
                    $q->whereColumn('amount_paid', '<', 'amount');
                    if ($since) {
                        $q->orWhere('updated_at', '>', $since);
                    }
                })
                ->orderBy('due_date')
                ->get(),

            'customer_advances' => fn () => CustomerAdvance::query()
                ->where('is_active', true)
                ->orderByDesc('advance_date')
                ->get(),

            // 🔴→✅ TICKET 14.76 — LES RELANCES DEJA FAITES DESCENDENT.
            //
            // ⚠️⚠️ SANS ELLES, LE POSTE RELANCE DEUX FOIS. La table existe et
            // vit : `RelancesClients` (web) l'alimente a chaque envoi WhatsApp,
            // mail ou SMS. Un poste qui l'ignore montre une file de relance ou
            // rien ne distingue le debiteur relance ce matin de celui qu'on n'a
            // jamais contacte — et le KPI « Relances Effectuees » de la maquette
            // n'a aucune source.
            //
            // ⚠️ SANS FILTRE `since`, comme les creances : une relance faite il y
            // a trois semaines n'a plus bouge depuis, et c'est justement celle qui
            // dit qu'il ne faut pas rappeler aujourd'hui.
            //
            // ⚠️ SERVIE EN LECTURE SEULE. Envoyer une relance suppose le reseau ET
            // le canal mail du serveur (`CustomerReminderMail`) : le poste hors
            // ligne ne peut pas le faire, et l'y autoriser creerait des relances
            // que `customer_reminders` n'enregistrerait jamais.
            'customer_reminders' => fn () => CustomerReminder::query()
                ->orderByDesc('reminder_date')
                ->get(['id', 'customer_id', 'receivable_id', 'channel', 'reminder_date', 'message']),

            // 🔴→✅ TICKET 14.77 — LES DEUX DERNIERS REFERENTIELS D'ELEVAGE.
            //
            // ⚠️ LE POSTE N'A PAS DE TABLE DES ESPECES : le libelle voyage AVEC le
            // type d'aliment, comme le code espece voyage avec la bande (F0.14).
            // Sans lui, la colonne « Espece Cible » de l'ecran Parametres Elevage
            // n'aurait qu'un UUID a afficher.
            'feed_types' => fn () => FeedType::with('species')
                ->where('is_active', true)
                ->orderBy('name')
                ->get()
                ->map(function (FeedType $type) {
                    return [
                        'id' => $type->id,
                        'name' => $type->name,
                        'species_id' => $type->species_id,
                        'species_code' => $type->species?->code,
                        'species_label' => $type->species?->label,
                        'standard_bag_weight_kg' => $type->standard_bag_weight_kg,
                        'price_per_kg' => $type->price_per_kg,
                    ];
                }),

            // ⚠️ TABLE SINGLETON — une seule ligne, `current()` la cree au besoin.
            // Ces prefixes nomment les animaux sur le terrain (R1, T1, LOT-VOL-1) :
            // un poste qui les ignore proposerait sa propre convention, et deux
            // registres de la meme ferme ne se liraient plus ensemble.
            'elevage_numbering' => fn () => ElevageNumberingSetting::current()->only([
                'bande_format', 'lapine_prefix', 'male_prefix', 'truie_prefix',
                'verrat_prefix', 'portee_prefix', 'volaille_prefix', 'parc_prefix',
                'escargot_prefix',
            ]),

            // 🔴→✅ TICKET 14.78 — LE DOMAINE ACHAT DESCEND AU POSTE.
            //
            // ⚠️⚠️ SANS LES FOURNISSEURS, LE POSTE NE PEUT RIEN ACHETER HORS LIGNE.
            // C'est la meme dependance que les clients pour la caisse (14.75) : un
            // achat sans fournisseur serait rejete a l'envoi, et l'operateur ne
            // comprendrait pas pourquoi.
            'suppliers' => fn () => Supplier::query()
                ->where('is_active', true)
                ->orderBy('name')
                ->get(['id', 'name', 'category', 'phone', 'email', 'address']),

            // Ticket 15.20 (D8) : créance OUVERTE par fournisseur (part payée des achats retournés - remboursements déjà
            // encaissés). Servie CALCULÉE, sans filtre `since` (comme les dettes) : le poste en a besoin pour ne pas
            // proposer un remboursement que le serveur plafonnerait. Seuls les fournisseurs > 0 sont listés.
            'supplier_credits' => fn () => Supplier::query()
                ->whereIn('id', Purchase::whereNotNull('returned_at')->where('supplier_credit', '>', 0)->pluck('supplier_id'))
                ->get(['id', 'name'])
                ->map(fn (Supplier $f) => [
                    'supplier_id' => $f->id,
                    'supplier_name' => $f->name,
                    'open_credit' => app(\App\Services\SupplierRefundService::class)->creanceOuverte($f->id),
                ])
                ->filter(fn (array $c) => $c['open_credit'] > 0)
                ->values(),

            // ⚠️ LE MONTANT D'UN BON DE COMMANDE N'EST PAS STOCKE : il se somme sur
            // ses lignes. Le servir calcule evite que le poste le recompose a sa
            // facon — et que les deux surfaces affichent deux estimations.
            'purchase_orders' => fn () => PurchaseOrder::with(['supplier', 'lines'])
                ->orderByDesc('created_at')
                ->get()
                ->map(fn (PurchaseOrder $bon) => [
                    'id' => $bon->id,
                    'supplier_id' => $bon->supplier_id,
                    'supplier_name' => $bon->supplier?->name,
                    'expected_delivery_date' => $bon->expected_delivery_date?->format('Y-m-d'),
                    'status' => $bon->status,
                    'created_at' => $bon->created_at?->toIso8601String(),
                    // ⚠️ LA COLONNE S'APPELLE `estimated_unit_price`, PAS
                    // `unit_price` — c'est un PRIX ESTIME, la commande n'etant pas
                    // encore livree. Ecrit `unit_price` par habitude, le total
                    // valait 0 pour un bon de 405 000 FCFA : pas un tiret, un
                    // CHIFFRE FAUX, que rien a l'ecran n'aurait signale.
                    'estimated_total' => $bon->lines->sum(
                        fn ($ligne) => (float) $ligne->qty * (float) $ligne->estimated_unit_price
                    ),
                ]),

            // 🔴→✅ TICKET 14.79 — LES DETTES FOURNISSEURS DESCENDENT.
            //
            // ⚠️ MEME REGLE QUE LES CREANCES CLIENTS (14.75) : seul ce qui RESTE
            // DU est servi, SANS filtre `since`. Une dette echue il y a trois mois
            // n'a plus bouge depuis — et c'est precisement celle que le
            // fournisseur va reclamer. Le poste remplacant sa table a chaque
            // tirage, une dette soldee entre-temps en disparait proprement.
            //
            // ⚠️ LE NOM DU FOURNISSEUR VOYAGE AVEC LA DETTE : sans lui, la colonne
            // « Fournisseur » de l'ecran Dettes n'aurait qu'un UUID a afficher.
            'payables' => fn () => Payable::with('supplier')
                ->whereColumn('amount_paid', '<', 'amount')
                ->orderBy('due_date')
                ->get()
                ->map(fn (Payable $dette) => [
                    'id' => $dette->id,
                    'supplier_id' => $dette->supplier_id,
                    'supplier_name' => $dette->supplier?->name,
                    'purchase_id' => $dette->purchase_id,
                    'amount' => $dette->amount,
                    'amount_paid' => $dette->amount_paid,
                    'due_date' => $dette->due_date?->format('Y-m-d'),
                    'status' => $dette->status,
                ]),

            // 🔴→✅ TICKET 14.81 — LE PERSONNEL ET SON POINTAGE DESCENDENT.
            //
            // ⚠️⚠️ LE POINTAGE EST L'ACTE DE TERRAIN PAR EXCELLENCE : il se fait a
            // 7 h a la ferme, ou le reseau n'est pas. Sans les employes au poste,
            // il n'y a personne a pointer ; sans les pointages deja saisis, le
            // chef d'equipe repointe quelqu'un que le web connait deja.
            'employees' => fn () => Employee::query()
                ->where('is_active', true)
                ->orderBy('last_name')
                ->get(['id', 'first_name', 'last_name', 'position', 'base_salary', 'hire_date', 'status'])
                // 🔴→✅ TICKET S3 — LE SALAIRE NE DESCEND QU'AUX RÔLES RH. Il partait vers tout poste connecté,
                // caissier compris. Sans `view-rh`, le poste reçoit `null` et affiche « — » (salaire inconnu).
                ->each(function (Employee $employe) use ($request) {
                    if (! $request->user()?->can('view-rh')) {
                        $employe->base_salary = null;
                    }
                }),

            // ⚠️ UN STAGIAIRE N'EST PAS UN EMPLOYE : la table est autonome, sans
            // relation vers `employees` — c'est aussi pourquoi la feuille de
            // pointage ne le couvre pas (ses absences vivent dans
            // `internship_absences`).
            'internships' => fn () => Internship::query()
                ->orderByDesc('start_date')
                ->get(),

            // ⚠️ BORNE A 60 JOURS, ET C'EST DELIBERE. La table porte deja 870
            // lignes et grossit d'une par employe et par jour : la servir en
            // entier alourdirait chaque tirage pour une donnee que personne ne
            // consulte au-dela du mois courant. Le poste a besoin du mois en
            // cours pour ne pas repointer ; l'historique vit sur le web.
            'attendance_records' => fn () => AttendanceRecord::query()
                ->where('is_active', true)
                ->where('attendance_date', '>=', now()->subDays(60)->toDateString())
                ->orderByDesc('attendance_date')
                ->get(['id', 'employee_id', 'attendance_date', 'check_in', 'check_out', 'status'])
                ->map(fn (AttendanceRecord $p) => [
                    'id' => $p->id,
                    'employee_id' => $p->employee_id,
                    // ⚠️⚠️ LE JOUR SE SERT EN 'Y-m-d', JAMAIS EN INSTANT. Eloquent
                    // serialise une colonne `date` en « 2026-08-16T23:00:00Z » : le
                    // 17 aout local devient le 16 a 23 h UTC, et un poste qui lit
                    // l'instant sans le ramener a l'heure locale pointe la veille.
                    // Le meme piege a deja coute une echeance de creance (14.75).
                    'attendance_date' => $p->attendance_date?->format('Y-m-d'),
                    'check_in' => $p->check_in,
                    'check_out' => $p->check_out,
                    'status' => $p->status,
                ]),

            // 🔴→✅ TICKET 14.82 — LE SECRETARIAT DESCEND AU POSTE.
            //
            // ⚠️ Au 09/10/2026 (tickets 15.23, 15.24, 15.25), `mails`, `archived_documents` et
            // `administrative_documents` s'ECRIVENT au poste (`pushMails`, `pushArchivedDocuments`,
            // `pushAdministrativeDocuments`) : aucune de ces trois tables n'est plus en consultation pure.
            // Aucune piece jointe, en-tete officielle ni signature n'est portee par ces tables.
            //
            // ⚠️ LES DATES SE SERVENT EN 'Y-m-d', jamais en instant : le meme
            // piege que le pointage (14.81) et l'echeance de creance (14.75).
            //
            // ⚠️ TICKET 15.23 — `mails` S'ECRIT AU POSTE (`pushMails`). Le tirage sert tous les
            // courriers ACTIFS (complet, non incrémental, comme avant) ET les courriers ARCHIVÉS
            // depuis `since` avec `is_active = false` : sans eux, un poste qui fusionne par
            // identifiant ne saurait jamais qu'un courrier a été archivé ailleurs. `updated_at`
            // est servi (instant ISO) pour que le poste départage une version locale d'une
            // version serveur. Les dates restent en 'Y-m-d'.
            'mails' => fn () => Correspondence::query()
                ->where(function ($q) use ($since) {
                    $q->where('is_active', true);
                    if ($since) {
                        $q->orWhere('updated_at', '>', $since);
                    }
                })
                ->orderByDesc('mail_date')
                ->get()
                ->map(fn (Correspondence $c) => [
                    'id' => $c->id,
                    'reference' => $c->reference,
                    'type' => $c->type,
                    'subject' => $c->subject,
                    'party' => $c->party,
                    'mail_date' => $c->mail_date?->format('Y-m-d'),
                    'is_active' => (bool) $c->is_active,
                    'updated_at' => $c->updated_at?->toIso8601String(),
                ]),

            // Ticket DEV — `quotes` S'ÉCRIT AU POSTE (`pushQuotes`) : table MIXTE, tirée ET saisie. Tous les devis, archivés
            // compris (`is_active`), au tirage complet ; depuis `since`, ceux créés, modifiés, avancés ou archivés. Le
            // numéro `DEV-AAAA-NNN` est celui du serveur (le poste ne l'invente jamais). Dates en 'Y-m-d' (une DATE, jamais
            // un instant : piège de l'échéance 14.75), `updated_at` en ISO pour départager. Le poste ne remplace jamais un
            // devis qu'il a en attente ou en conflit.
            'quotes' => fn () => Quote::query()
                ->with('sale')
                ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
                ->orderBy('quote_date')
                ->orderBy('id')
                ->get()
                ->map(fn (Quote $d) => [
                    'id' => $d->id,
                    'quote_number' => $d->quote_number,
                    'customer_id' => $d->customer_id,
                    'articles_description' => $d->articles_description,
                    'amount' => (float) $d->amount,
                    'tva_rate' => (float) $d->tva_rate,
                    'validity_days' => (int) $d->validity_days,
                    'quote_date' => $d->quote_date?->format('Y-m-d'),
                    'note' => $d->note,
                    'status' => $d->status,
                    'is_active' => (bool) $d->is_active,
                    // Ticket DEV3 — le lien vers la facture d'un devis converti (`null` avant) et son numéro `FV-AAAA-XXXXXX`.
                    'converted_sale_id' => $d->converted_sale_id,
                    'invoice_number' => $d->numero_facture,
                    'updated_at' => $d->updated_at?->toIso8601String(),
                ]),

            // ⚠️ TICKET 15.25 — `administrative_documents` S'ECRIT AU POSTE
            // (`pushAdministrativeDocuments`), mêmes principes que `mails` et `archived_documents` :
            // tous les documents ACTIFS à chaque tirage, PLUS les RETIRÉS (`is_active = false`) dont
            // `updated_at > since`. `is_active` et `updated_at` (ISO 8601) sont servis. Dates en 'Y-m-d'.
            'administrative_documents' => fn () => AdministrativeDocument::query()
                ->where(function ($q) use ($since) {
                    $q->where('is_active', true);
                    if ($since) {
                        $q->orWhere('updated_at', '>', $since);
                    }
                })
                ->orderByDesc('doc_date')
                ->get()
                ->map(fn (AdministrativeDocument $d) => [
                    'id' => $d->id,
                    'title' => $d->title,
                    'type' => $d->type,
                    'beneficiary' => $d->beneficiary,
                    'doc_date' => $d->doc_date?->format('Y-m-d'),
                    'status' => $d->status,
                    'is_active' => (bool) $d->is_active,
                    'updated_at' => $d->updated_at?->toIso8601String(),
                ]),

            // ⚠️ TICKET 15.24 — `archived_documents` S'ECRIT AU POSTE (`pushArchivedDocuments`),
            // mêmes principes que `mails` : tous les documents ACTIFS à chaque tirage, PLUS les
            // RETIRÉS (`is_active = false`) dont `updated_at > since`. `is_active` et `updated_at`
            // (ISO 8601) sont servis. Le STATUT n'est PAS servi : il se déduit de `expiry_date`
            // (règle `ArchivedDocument::statutPour`, seuil 30 jours). Dates en 'Y-m-d'.
            'archived_documents' => fn () => ArchivedDocument::query()
                ->where(function ($q) use ($since) {
                    $q->where('is_active', true);
                    if ($since) {
                        $q->orWhere('updated_at', '>', $since);
                    }
                })
                ->orderByDesc('archived_date')
                ->get()
                ->map(fn (ArchivedDocument $a) => [
                    'id' => $a->id,
                    'title' => $a->title,
                    'category' => $a->category,
                    'archived_date' => $a->archived_date?->format('Y-m-d'),
                    'expiry_date' => $a->expiry_date?->format('Y-m-d'),
                    'is_active' => (bool) $a->is_active,
                    'updated_at' => $a->updated_at?->toIso8601String(),
                ]),

            // 🔴→✅ TICKET 14.83 — LE JOURNAL COMPTABLE DESCEND AU POSTE.
            //
            // ⚠️⚠️ LES ETATS LISENT LE JOURNAL, JAMAIS DES TABLES METIER
            // DISJOINTES. C'est la regle du projet depuis l'origine : un Grand
            // Livre ou une Balance recomposes a partir des ventes et des achats
            // donneraient deux comptabilites differentes pour la meme ferme. Pour
            // que le poste puisse AFFICHER ces etats, il lui faut donc le journal
            // lui-meme — pas des agregats prepares.
            //
            // ⚠️ VOLUME MAITRISE : 34 comptes, 516 ecritures, 1337 lignes pour
            // l'exercice ouvert. Le filtre `since` porte sur les ecritures ; les
            // comptes et l'exercice, eux, descendent en entier — sans le plan
            // comptable, une ligne d'ecriture n'a qu'un UUID a montrer.
            'chart_of_accounts' => fn () => ChartOfAccount::query()
                ->where('is_active', true)
                ->orderBy('code')
                ->get(['id', 'code', 'label', 'class']),

            'fiscal_years' => fn () => FiscalYear::query()
                ->orderByDesc('year')
                ->get(['id', 'year', 'start_date', 'end_date', 'status'])
                ->map(fn (FiscalYear $e) => [
                    'id' => $e->id,
                    'year' => $e->year,
                    'start_date' => $e->start_date?->format('Y-m-d'),
                    'end_date' => $e->end_date?->format('Y-m-d'),
                    'status' => $e->status,
                ]),

            // 🔴→✅ TICKET 14.84 — LES PARAMETRES GENERAUX DESCENDENT.
            //
            // ⚠️⚠️ AUCUN SECRET NE QUITTE LE SERVEUR. `company_settings` porte
            // `smtp_password_encrypted`, `twilio_auth_token_encrypted` et
            // `vonage_api_secret_encrypted` : un poste vole donnerait acces au
            // compte SMS et a la boite mail de la ferme. Seule l'IDENTITE de
            // l'entreprise et ses TAUX descendent — jamais un identifiant de
            // service, meme chiffre.
            'company_settings' => function () {
                $entreprise = CompanySetting::query()->first();

                return $entreprise === null ? null : [
                    'company_name' => $entreprise->company_name,
                    'promoter_name' => $entreprise->promoter_name,
                    'address' => $entreprise->address,
                    'phone' => $entreprise->phone,
                    'email' => $entreprise->email,
                    'ifu' => $entreprise->ifu,
                    'rccm' => $entreprise->rccm,
                    'tva_enabled' => $entreprise->tva_enabled,
                    'tva_default_rate' => $entreprise->tva_default_rate,
                    // Ticket H9b — délai du rappel des soins (R-SOINS-01), réglable au poste comme au web.
                    'rappel_soins_jours' => $entreprise->rappel_soins_jours,
                ];
            },

            // ⚠️⚠️ UN MODULE DESACTIVE DOIT DISPARAITRE DE L'ECRAN, PAS SEULEMENT
            // DE LA BASE. `modules_config` dit quelles especes la ferme exploite :
            // l'heliciculture est desactivee ici, et le poste continuait de
            // proposer la fiche Escargots. La maquette, elle, masque les blocs
            // `data-module="helico"`.
            'modules_config' => fn () => ModuleConfig::query()
                ->orderBy('species_code')
                ->get(['id', 'species_code', 'is_enabled']),

            // ⚠️⚠️ `App\Models\Role`, JAMAIS `Spatie\Permission\Models\Role`.
            // Le modele de Spatie n'a pas `HasUuids` : il declare sa cle
            // auto-incrementee et Eloquent CASTE alors `roles.id` en entier. Un
            // UUID « 01a01168-... » devient « 1 » — les quatre roles descendaient
            // au poste avec le MEME identifiant, et la relation `permissions` ne
            // retrouvait plus aucune ligne du pivot. Le projet avait deja documente
            // ce piege sur le seeder (voir `App\Models\Role`) ; ce tirage l'a
            // repete. Le poste l'a signale au premier tirage reel : contrainte
            // d'unicite violee sur `roles_applicatifs.id`.
            'roles' => fn () => Role::query()
                ->with('permissions:id,name')
                ->orderBy('name')
                ->get()
                ->map(fn ($role) => [
                    'id' => (string) $role->id,
                    'name' => $role->name,
                    'permissions' => $role->permissions->pluck('name')->all(),
                ]),

            // ⚠️ NI MOT DE PASSE NI JETON : la liste sert a SAVOIR QUI travaille
            // sur la ferme, pas a s'authentifier.
            'users' => fn () => User::query()
                ->orderBy('name')
                ->get(['id', 'name', 'username', 'email', 'is_active'])
                ->map(fn (User $u) => [
                    'id' => $u->id,
                    'name' => $u->name,
                    'username' => $u->username,
                    'email' => $u->email,
                    'is_active' => $u->is_active,
                    'role' => $u->getRoleNames()->first(),
                ]),

            // ⚠️ BORNE A 100 LIGNES : la table grossit d'une ligne par action et
            // n'a d'interet, au poste, que pour les dernieres.
            // 🔴→✅ TICKET S3 — LE JOURNAL D'AUDIT (qui a fait quoi, depuis quelle adresse IP) est réservé aux comptes
            // qui gèrent les utilisateurs, comme son écran web. Les autres postes reçoivent une liste vide.
            'audit_logs' => fn () => AuditLog::query()
                ->when(! $request->user()?->can('manage-users'), fn ($q) => $q->whereRaw('1 = 0'))
                ->with('user:id,name')
                ->orderByDesc('created_at')
                // Ticket U14 — les deux cents lignes de la liste du web (`AuditLogs::getLogsProperty()`, `limit(200)`),
                // et non cent : l'onglet du poste montre la même liste.
                ->limit(200)
                ->get()
                ->map(fn (AuditLog $log) => [
                    'id' => $log->id,
                    'user_name' => $log->user?->name,
                    'action' => $log->action,
                    'module' => $log->module,
                    'ip_address' => $log->ip_address,
                    'created_at' => $log->created_at?->toIso8601String(),
                ]),

            // ⚠️ TICKET 15.10 — LES NOTIFICATIONS DESCENDENT ENFIN AU POSTE.
            //
            // Elles vivaient uniquement côté web : la cloche du poste n'avait ni
            // compteur ni liste. Seules celles que l'UTILISATEUR DU JETON peut voir
            // sont servies (`visibleTo` : adressées à lui ou diffusées à l'un de ses
            // rôles) — jamais celles d'un autre. La CATÉGORIE est calculée ici, par
            // le modèle : la recopier au poste ferait dériver deux tables dès
            // l'ajout d'un type.
            //
            // ⚠️ PAS DE FILTRE `since`, ET BORNE A 200 : l'état « lue » et la
            // suppression changent sans toucher `created_at`, et un tirage
            // incrémental ne les verrait pas. Le poste remplace l'ensemble.
            'notifications' => fn () => Notification::query()
                ->visibleTo($request->user())
                ->latest('created_at')
                ->limit(200)
                ->get()
                ->map(fn (Notification $n) => [
                    'id' => $n->id,
                    'type' => $n->type,
                    'category' => $n->category,
                    'severity' => $n->severity,
                    'title' => $n->title,
                    'message' => $n->message,
                    'link_url' => $n->link_url,
                    'is_read' => $n->is_read,
                    'created_at' => $n->created_at?->toIso8601String(),
                ]),

            // ⚠️ TICKET 15.12 — LES REVENUS PAR BANDE DESCENDENT, CALCULÉS ICI.
            //
            // Le poste ne reçoit des ventes serveur que l'en-tête (`$factures`, sans
            // lignes) : il ne sait pas quelle bande a vendu quoi, et un revenu par
            // bande recalculé au poste ne compterait que SES ventes. Le chiffre est
            // donc produit par `LotRevenueService` — le même que la page web — et
            // servi tel quel : ventes validées, nettes des avoirs traités.
            //
            // ⚠️ PAS DE FILTRE `since` : un avoir traité ou une annulation changent le
            // revenu sans toucher la ligne de vente. Le poste remplace l'ensemble.
            'lot_revenues' => fn () => collect(app(LotRevenueService::class)->forLots())
                ->flatMap(fn (array $lignes, string $lotId) => collect($lignes)->map(fn (array $l) => [
                    'lot_id' => $lotId,
                    'product_id' => $l['product_id'],
                    'label' => $l['label'],
                    'amount' => $l['montant'],
                ]))
                ->values(),

            // ⚠️ TICKET 15.14 — LES SUJETS SUIVIS INDIVIDUELLEMENT DESCENDENT.
            //
            // Sans eux le poste ne connaissait aucun sujet NOMMÉ : seulement les
            // références texte (« R1 », « LAP-2026-0143 ») des saillies. Il ne pouvait
            // donc pas ouvrir la fiche d'un reproducteur.
            //
            // ⚠️ TOUS LES SUJETS, SORTIS COMPRIS : la fiche d'un animal vendu ou mort
            // reste consultable (c'est son historique). Pas de filtre `since` — un
            // changement de cage ou de statut doit redescendre, et la table (des
            // reproducteurs, pas du cheptel) reste petite. Le poste remplace l'ensemble.
            //
            // ⚠️ LE LIBELLÉ D'ESPÈCE ET LE CODE DE LA BANDE VOYAGENT AVEC LE SUJET : le
            // poste n'a pas de table des espèces, et la bande peut ne pas lui être
            // descendue.
            'animals' => fn () => Animal::query()
                ->with(['species:id,label', 'lot:id,code'])
                ->orderBy('identifier')
                ->get()
                ->map(fn (Animal $a) => [
                    'id' => $a->id,
                    'identifier' => $a->identifier,
                    // Ticket BS3 — l'identifiant de l'espèce descend aussi : le poste écrit désormais un sujet (envoi `animals`).
                    'species_id' => $a->species_id,
                    'species_label' => $a->species?->label,
                    'lot_id' => $a->lot_id,
                    'lot_code' => $a->lot?->code,
                    'category' => $a->category,
                    'sex' => $a->sex,
                    'breed' => $a->breed,
                    'birth_date' => $a->birth_date?->format('Y-m-d'),
                    'entry_date' => $a->entry_date?->format('Y-m-d'),
                    'origin' => $a->origin,
                    'cage' => $a->cage,
                    'status' => $a->status,
                    'exit_date' => $a->exit_date?->format('Y-m-d'),
                    'exit_reason' => $a->exit_reason,
                    'is_active' => $a->is_active,
                ]),

            // ⚠️ TICKET 15.15 — LES ESPÈCES D'ÉLEVAGE ACTIVES DESCENDENT.
            //
            // Le formulaire « Ajouter un Produit » propose la « Filière d'élevage »
            // (`products.species_id`) ; le poste n'avait aucune table des espèces. Seules
            // celles que la ferme exploite sont servies (`enabled()` : module actif) —
            // proposer une espèce éteinte laisserait créer un produit pour une filière
            // que l'exploitant a désactivée. Pas de filtre `since` : table de quelques
            // lignes, remplacée à chaque tirage.
            'livestock_species' => fn () => LivestockSpecies::query()
                ->enabled()
                ->orderBy('label')
                ->get(['id', 'code', 'label'])
                ->map(fn (LivestockSpecies $e) => [
                    'id' => $e->id,
                    'code' => $e->code,
                    'label' => $e->label,
                ]),

            // ⚠️ TICKET 15.13 — LES MODÈLES D'ATTESTATION ET LE NOMBRE D'ATTESTATIONS
            // ÉMISES DESCENDENT.
            //
            // Les deux modèles (employé, stagiaire) sont TOUJOURS servis : `forType`
            // crée le modèle par défaut s'il n'existe pas, pour que le poste ne
            // découvre jamais « aucun modèle » sur une ferme neuve.
            //
            // ⚠️ LE COMPTEUR EST UN DÉCOMPTE D'AUDIT, PAS UNE TABLE : Laravel n'a pas de
            // table d'attestations émises, seulement les lignes `attestation.generated.*`.
            // Le poste ne détient que les cent dernières lignes d'audit de la ferme ; il
            // ne peut donc pas recompter — le serveur le fait sur l'historique entier.
            'attestation_templates' => fn () => collect(AttestationService::TYPES)
                ->map(fn (string $type) => AttestationTemplate::forType($type))
                ->map(fn (AttestationTemplate $m) => [
                    'id' => $m->id,
                    'type' => $m->type,
                    'body_text' => $m->body_text,
                ])
                ->values(),
            'attestation_counts' => fn () => app(AttestationService::class)->compteurs(),

            // ⚠️ SANS FILTRE `since` : la liste est courte et le poste doit
            // toujours pouvoir proposer un compte payeur, meme apres un tirage
            // incremental ou rien n'a change.
            // ⚠️ TICKET 14.62 — CE QU'IL FAUT POUR SAISIR UNE DEPENSE HORS
            // LIGNE. Sans les comptes de tresorerie, le poste ne peut pas dire
            // QUI paie ; sans la liste des comptes de charge, il devrait la
            // recopier et les deux listes divergeraient au premier ajout.
            'treasury_accounts' => fn () => \App\Models\TreasuryAccount::query()
                ->where('is_active', true)
                ->orderBy('label')
                ->get(['id', 'label', 'account_code', 'type', 'balance']),
            // Ticket DEP3 — N'EST PLUS LU PAR LE POSTE MIGRÉ (le compte de charge d'une ligne se choisit dans le plan
            // comptable, classe 6) ; CONSERVÉ pour les postes non migrés, qui l'attendent (le serveur est déployé avant eux).
            'expense_categories' => fn () => \App\Models\Expense::CATEGORIES,
            // 🔴→✅ TICKET ARC2 — LA CORBEILLE DESCEND AU POSTE, EN INSTANTANÉ (page 1, remplacé en entier à chaque tirage).
            //
            // Une ligne par élément archivé de `CorbeilleService::registre()`, AVEC ce que le serveur en permet
            // (`restaurable` / `supprimable` et le motif du refus) : le poste n'a pas à recalculer les règles (dépenses
            // contre-passées, exercice clos, code pris, références dans une vingtaine de tables) — deux implémentations
            // finiraient par diverger. `id` = UUID v5 de (type, id de l'élément) : stable d'un tirage à l'autre, jamais
            // celui de la ligne métier (une ligne supprimée n'a plus d'identité). ⚠️ AGRÈGE LES ARCHIVES DE TOUS LES
            // MODULES : vide pour un compte sans `manage-parametres` — y compris sur la réponse complète des postes
            // anciens, qui ne filtre pas les tables par permission.
            'corbeille' => fn () => $request->user()?->can('manage-parametres')
                ? collect(app(\App\Services\CorbeilleService::class)->elements())->map(fn (array $e) => [
                    'id' => \Ramsey\Uuid\Uuid::uuid5(\App\Services\CorbeilleService::ESPACE_CORBEILLE, $e['type'].':'.$e['id'])->toString(),
                    'type' => $e['type'],
                    'element_id' => $e['id'],
                    'titre' => $e['titre'],
                    'detail' => $e['detail'],
                    'module' => $e['module'],
                    // Heure murale du serveur (le jour d'archivage du web), jamais convertie.
                    'archive_le' => $e['archive_le']?->format('Y-m-d H:i:s'),
                    'restaurable' => $e['restaurable'],
                    'motif_restauration' => $e['motif_restauration'],
                    'supprimable' => $e['supprimable'],
                    'motif_suppression' => $e['motif_suppression'],
                ])->values()
                : collect(),
            // Ticket DEP3 — centres de coût (filières) : le Centre de Coût facultatif de l'en-tête d'une dépense.
            'cost_centers' => fn () => \App\Models\CostCenter::query()
                ->orderBy('label')
                ->get(['id', 'label', 'type', 'parent_species_id', 'is_active'])
                ->map(fn ($c) => [
                    'id' => $c->id, 'label' => $c->label, 'type' => $c->type,
                    'parent_species_id' => $c->parent_species_id, 'is_active' => (bool) $c->is_active,
                ]),
        ];
    }

    /**
     * Ticket S-T4 — tables d'HISTORIQUE, servies par pièce : en entier au tirage complet, découpées en pages au tirage
     * paginé (voir [pageDeFamille]). Une famille :
     *  - `cle` : clé de la réponse ; `requete` : la requête et son filtre `since` (inchangés depuis avant S-T4) ;
     *  - `historique` : l'ordre du tirage complet d'avant S-T4 (le tirage paginé ordonne par (`updated_at`, `id`)) ;
     *  - `enJson` : sérialisation de la pièce (aucune : le modèle tel quel) ;
     *  - `lignes` : clé de la réponse → [colonne de la pièce, lecture de TOUTES les lignes des pièces servies] ;
     *  - `sansBorne` : la pièce n'est pas bornée au début du tirage (journal comptable, voir plus bas).
     *
     * ⚠️ L'ordre des familles est celui des pages : aucune ne dépend d'une autre (bandes, produits, exercices et plan
     * comptable descendent à la page 1). Le journal vient en DERNIER : sa liste d'écritures actives est servie juste
     * après lui, à la dernière page.
     *
     * @return array<int, array<string, mixed>>
     */
    private function famillesPaginees(?Carbon $since): array
    {
        $dettesParAchat = null;

        return [
            [
                'cle' => 'livestock_daily_entries',
                'requete' => fn () => LivestockDailyEntry::query()->when($since, fn ($q) => $q->where('updated_at', '>', $since)),
            ],
            [
                // Ticket 15.46 — transferts entre bandes : source de vérité des colonnes `transfert_*` des fiches (servies
                // ci-dessus avec la fiche). Le poste les affiche et peut en créer ou en annuler hors ligne.
                'cle' => 'livestock_transfers',
                'requete' => fn () => LivestockTransfer::query()
                    ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
                    ->select(['id', 'source_lot_id', 'target_lot_id', 'transfer_date', 'quantity', 'categorie', 'constitution',
                        'motif', 'is_active', 'updated_at']),
            ],
            [
                // Ticket U3 (décision D-U3 du 19/10/2026 : archivage d'un soin au poste comme au web) — `is_active` est
                // servi. Tirage complet : les soins ACTIFS seuls (un poste neuf n'a que faire des archivés). Tirage
                // incrémental : tout soin modifié depuis `since`, ARCHIVÉS COMPRIS — sans eux, un poste ne saurait jamais
                // qu'un soin a été archivé au web et le compterait encore (registre, coût sanitaire, protocole du jour).
                'cle' => 'veterinary_records',
                'requete' => fn () => VeterinaryRecord::query()
                    ->when(
                        $since,
                        fn ($q) => $q->where('updated_at', '>', $since),
                        fn ($q) => $q->where('is_active', true),
                    ),
            ],
            [
                // Ticket H8b (décision D-H8 du 19/10/2026) — l'infirmerie et le calendrier vétérinaire PLANIFIÉ descendent
                // au poste : sans eux, l'onglet « Suivi Sanitaire » et le calendrier restaient vides hors ligne.
                'cle' => 'infirmary_records',
                'requete' => fn () => \App\Models\InfirmaryRecord::query()
                    ->when($since, fn ($q) => $q->where('updated_at', '>', $since)),
            ],
            [
                'cle' => 'veterinary_calendar_events',
                'requete' => fn () => \App\Models\VeterinaryCalendarEvent::query()
                    ->when($since, fn ($q) => $q->where('updated_at', '>', $since)),
            ],
            [
                // 🔴→✅ TICKET 14.72 — LE CYCLE DE REPRODUCTION DESCEND AU POSTE.
                //
                // `livestock_reproduction_events` est la SEULE table du systeme qui
                // suive une femelle NOMMEE (R1, R2… / T1, T2…) : les fiches
                // journalieres ne connaissent que des agregats de bande. Sans elle, le
                // poste ne pouvait ni afficher l'ecran Suivi Reproduction, ni — defaut
                // deja signale par `SoinsRepository` — calculer le jour de cycle d'une
                // bande en reproduction, dont le protocole se compte depuis la
                // DERNIERE SAILLIE.
                //
                // ⚠️ LES CYCLES EN COURS DESCENDENT SANS FILTRE `since`, meme regle
                // que les remanences : une gestation ouverte il y a trois semaines n'a
                // pas bouge depuis, donc un tirage incremental la manquerait — et
                // c'est precisement l'evenement qu'un poste doit connaitre. Seul
                // l'historique clos est filtre.
                'cle' => 'livestock_reproduction_events',
                'requete' => fn () => $since
                    ? LivestockReproductionEvent::query()
                        ->where(fn ($q) => $q->where('status', 'en_cours')
                            ->orWhere('updated_at', '>', $since))
                    : LivestockReproductionEvent::query(),
                'historique' => fn ($q) => $q->orderByDesc('saillie_date'),
            ],
            [
                // ⚠️ LE NOM DU FOURNISSEUR ET SA CATEGORIE VOYAGENT AVEC L'ACHAT. Le
                // poste doit pouvoir afficher la liste meme si le fournisseur a ete
                // archive depuis — et le referentiel, lui, ne sert que les actifs.
                //
                // ⚠️ LE STATUT SE CALCULE ICI, PAS AU POSTE : « Dette fournisseur » des
                // qu'une dette reste ouverte sur la piece, « Paye entierement » sinon.
                // Le poste ne recoit pas `payables` — deux regles de statut donneraient
                // deux listes differentes pour la meme ferme.
                //
                // Ticket U4 (D-U4) — un achat dont une LIGNE a changé depuis `since` redescend aussi : ses lignes
                // ne voyagent qu'avec lui (voir `purchase_lines`). Ticket U8 : de même pour une ligne de RETOUR
                // (voir `purchase_returns`).
                'cle' => 'purchases',
                'requete' => fn () => Purchase::with('supplier')
                    ->when($since, fn ($q) => $q->where(fn ($w) => $this->pieceOuLigneModifiee($w, $since)
                        ->orWhereHas('returns', fn ($r) => $r->where('updated_at', '>', $since)))),
                'historique' => fn ($q) => $q->orderByDesc('purchase_date'),
                'enJson' => function (Purchase $achat) use (&$dettesParAchat) {
                    $dettesParAchat ??= Payable::query()
                        ->whereColumn('amount_paid', '<', 'amount')
                        ->pluck('purchase_id')
                        ->filter()
                        ->flip();

                    return [
                        'id' => $achat->id,
                        'supplier_id' => $achat->supplier_id,
                        'supplier_name' => $achat->supplier?->name,
                        'supplier_category' => $achat->supplier?->category,
                        'payment_mode' => $achat->payment_mode,
                        'total' => $achat->total,
                        'purchase_date' => $achat->purchase_date?->format('Y-m-d'),
                        'has_debt' => $dettesParAchat->has($achat->id),
                        // Ticket 15.20 : marqueur de RETOUR (descend via `updated_at`, touché par le retour) et part déjà
                        // payée devenue créance sur le fournisseur (409). Le poste ne calcule ni l'un ni l'autre.
                        'returned_at' => $achat->returned_at?->toIso8601String(),
                        'supplier_credit' => $achat->supplier_credit,
                    ];
                },
                'lignes' => [
                    // 🔴→✅ TICKET U4 (D-U4) — LES LIGNES DES ACHATS SERVIS DESCENDENT AVEC EUX.
                    //
                    // ⚠️⚠️ AU MÊME CURSEUR QUE LEUR PIÈCE, ET SEULEMENT POUR LES PIÈCES SERVIES : TOUTES les lignes de
                    // chaque achat servi (un achat modifié, ou dont une ligne l'est, renvoie la liste COMPLÈTE de ses
                    // lignes — le poste remplace alors celles qu'il tient, et une ligne retirée ici disparaît là-bas),
                    // JAMAIS une ligne d'un achat non servi (le poste la refuserait : pièce inconnue). Sans elles, le PMP
                    // (`computePmp()`, Σ qty × unit_price ÷ Σ qty sur TOUTES les lignes d'achat) et la marge du Top 5
                    // étaient incalculables au poste. `unit_price` est ici un VRAI prix unitaire (contrairement aux
                    // lignes de vente).
                    'purchase_lines' => ['purchase_id', fn (Collection $ids) => $this->lignesDesPieces(
                        \App\Models\PurchaseLine::class,
                        'purchase_id',
                        $ids,
                        fn ($ligne) => [
                            'id' => $ligne->id,
                            'purchase_id' => $ligne->purchase_id,
                            'product_id' => $ligne->product_id,
                            'product_name' => $ligne->product?->name,
                            'qty' => (float) $ligne->qty,
                            'unit_price' => (float) $ligne->unit_price,
                        ],
                    )],
                    // 🔴→✅ TICKET U8 — LES LIGNES DE RETOUR DES ACHATS SERVIS DESCENDENT AVEC EUX.
                    //
                    // La carte « Écarts / Retours » de la liste des achats compte des LIGNES de retour
                    // (`PurchaseReturn::count()` : une ligne par ligne d'achat retournée, `PurchaseReturnService`) ; le
                    // poste, qui ne les recevait pas, comptait des achats retournés. Même règle que `purchase_lines` :
                    // TOUTES les lignes de retour de chaque achat servi, au même curseur, JAMAIS une d'un achat non servi.
                    // `return_batch_id` est l'identifiant du RETOUR (celui que le poste a fourni s'il l'a saisi) ;
                    // `return_date` manque aux retours d'avant le ticket 15.20 : la date d'enregistrement en tient lieu,
                    // jamais une date inventée.
                    'purchase_returns' => ['purchase_id', fn (Collection $ids) => $this->lignesDesPieces(
                        \App\Models\PurchaseReturn::class,
                        'purchase_id',
                        $ids,
                        fn ($retour) => [
                            'id' => $retour->id,
                            'purchase_id' => $retour->purchase_id,
                            'return_batch_id' => $retour->return_batch_id,
                            'purchase_line_id' => $retour->purchase_line_id,
                            'product_id' => $retour->product_id,
                            'qty' => (float) $retour->qty,
                            'reason' => $retour->reason,
                            'return_date' => ($retour->return_date ?? $retour->created_at)?->format('Y-m-d'),
                        ],
                    )],
                ],
            ],
            [
                // 🔴→✅ TICKET 14.80 — LES FACTURES DESCENDENT AU POSTE.
                //
                // ⚠️⚠️ UNE FACTURE EST UNE VENTE, il n'existe pas de table `invoices` :
                // `sales.mecef_status` et `sales.mecef_qr_ref` portent la
                // normalisation fiscale (ticket 7.1). Sans ce bloc, l'ecran
                // Facturation du poste n'aurait montre que les ventes encaissees SUR
                // CE POSTE — la caissiere aurait cru la ferme a 3 factures le mois ou
                // elle en a 40, et n'aurait jamais vu qu'une transmission a echoue.
                //
                // ⚠️ FILTRE `since` : contrairement aux creances, une vente ancienne
                // n'a pas besoin de redescendre a chaque tirage. Le premier tirage les
                // apporte toutes, les suivants n'apportent que les nouvelles et celles
                // dont le statut MeCeF a change — une retransmission reussie touche
                // `updated_at`, donc elle redescend.
                //
                // ⚠️ LE NOM DU CLIENT VOYAGE AVEC LA FACTURE : le poste a bien la table
                // `customers` (14.75), mais une vente au comptant n'a pas de client, et
                // une vente d'un client archive doit rester nommee.
                // Ticket U4 (D-U4) — une vente dont une LIGNE a changé depuis `since` redescend aussi (voir `sale_lines`).
                'cle' => 'sales',
                'requete' => fn () => Sale::with('customer')
                    ->when($since, fn ($q) => $q->where(fn ($w) => $this->pieceOuLigneModifiee($w, $since))),
                'historique' => fn ($q) => $q->orderByEffectiveDate(),
                'enJson' => fn (Sale $vente) => [
                    'id' => $vente->id,
                    'customer_id' => $vente->customer_id,
                    'customer_name' => $vente->customer?->name,
                    'payment_mode' => $vente->payment_mode,
                    // Ticket AV2 — « Historique des Ventes » du poste = celui du web : colonne « Remise » et détail d'une vente
                    // (sous-total, remise, total). Sans eux le poste affichait 0 pour la remise d'une vente du web.
                    'subtotal' => $vente->subtotal,
                    'discount' => $vente->discount,
                    'total' => $vente->total,
                    'status' => $vente->status,
                    'mecef_status' => $vente->mecef_status,
                    'mecef_qr_ref' => $vente->mecef_qr_ref,
                    'sold_at' => $vente->date_effective?->toIso8601String(),
                ],
                'lignes' => [
                    // 🔴→✅ TICKET U4 (D-U4) — LES LIGNES DES VENTES SERVIES DESCENDENT AVEC ELLES.
                    //
                    // Même règle que `purchase_lines` : toutes les lignes de chaque vente servie, aucune d'une vente non
                    // servie. Sans elles, le Top 5 des produits et les « Ventes (mois) » porcines du Tableau de bord du
                    // poste ne comptaient que les ventes saisies SUR CE POSTE, quand le web les compte toutes.
                    // ⚠️ `manual_total_amount` EST LA SOURCE DE VÉRITÉ DU MONTANT de la ligne ; `unit_price` n'en est que
                    // l'affichage dérivé (`manual_total_amount / qty`) : les deux sont servis tels que stockés.
                    'sale_lines' => ['sale_id', fn (Collection $ids) => $this->lignesDesPieces(
                        \App\Models\SaleLine::class,
                        'sale_id',
                        $ids,
                        fn ($ligne) => [
                            'id' => $ligne->id,
                            'sale_id' => $ligne->sale_id,
                            'product_id' => $ligne->product_id,
                            'lot_id' => $ligne->lot_id,
                            'qty' => (float) $ligne->qty,
                            'unit_price' => (float) $ligne->unit_price,
                            'manual_total_amount' => (float) $ligne->manual_total_amount,
                        ],
                    )],
                ],
            ],
            [
                // 🔴→✅ TICKET AV1 — LES AVOIRS CLIENTS DESCENDENT AU POSTE (« Retours et Avoirs »).
                //
                // Une ligne par avoir (un avoir porte UN produit : `credit_notes.product_id`), sans lignes filles : table
                // d'historique paginée par pièce, au curseur (`updated_at`, `id`). `credit_note_number` (`AV-AAAA-NNN`)
                // est attribué par le serveur seul : une demande née sur un poste le reçoit ici, au tirage qui suit son
                // acquittement. `created_at` est le JOUR DU FAIT, servi en HEURE MURALE du serveur ('Y-m-d H:i:s', le web
                // n'en montre que le jour : `format('d/m/Y')`). `accounting_entry_id` ne descend pas (le poste ne tient
                // pas la comptabilité d'un avoir : il en lit le résultat au Journal).
                'cle' => 'credit_notes',
                'requete' => fn () => \App\Models\CreditNote::query()
                    ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
                    ->select(['id', 'credit_note_number', 'sale_id', 'product_id', 'qty', 'amount', 'reason', 'decision',
                        'inspection_notes', 'status', 'created_at', 'updated_at']),
                'historique' => fn ($q) => $q->orderBy('created_at')->orderBy('id'),
                'enJson' => fn (\App\Models\CreditNote $a) => [
                    'id' => $a->id,
                    'credit_note_number' => $a->credit_note_number,
                    'sale_id' => $a->sale_id,
                    'product_id' => $a->product_id,
                    'qty' => $a->qty === null ? null : (float) $a->qty,
                    'amount' => (float) $a->amount,
                    'reason' => $a->reason,
                    'decision' => $a->decision,
                    'inspection_notes' => $a->inspection_notes,
                    'status' => $a->status,
                    'created_at' => $a->created_at?->format('Y-m-d H:i:s'),
                ],
            ],
            [
                // 🔴→✅ TICKET U13 — LES DÉPENSES DESCENDENT AU POSTE, AVEC LEUR ARCHIVAGE.
                //
                // `expenses` n'était au poste qu'une table de SAISIE (envoyée, jamais tirée) : son « Recettes et
                // Dépenses » ignorait les dépenses saisies au web ou sur un autre poste, et comptait encore une dépense
                // de ce poste archivée ensuite au web (`SaisieDepenses::archiveExpense()` : montant réintégré, charge
                // contre-passée). Table d'HISTORIQUE (une ligne par dépense, sans lignes) : paginée par pièce au
                // curseur (`updated_at`, `id`), comme les soins.
                //
                // ⚠️ TIRAGE COMPLET : TOUTES LES DÉPENSES, ARCHIVÉES COMPRISES (contrairement aux soins, actifs seuls).
                // Un poste DÉJÀ EN SERVICE repart d'un tirage complet (règle du périmètre S-T4, ou resynchronisation
                // unique `depenses_resync_u13`) avec, en base, des dépenses qu'il a lui-même saisies et fait acquitter :
                // si l'une a été archivée au web depuis, seul ce tirage complet peut le lui dire. Volume : une ligne
                // par dépense, de quelques champs. Tirage incrémental : toute dépense créée, modifiée ou archivée
                // depuis `since`.
                //
                // ⚠️ `expense_date` en 'Y-m-d' (une DATE : jamais un instant, piège de l'échéance 14.75) ; `amount` tel
                // que stocké ; `is_active` ; `updated_at` (instant ISO) pour le poste. Le justificatif ne descend pas
                // (aucun fichier ne voyage). Le poste ne remplace jamais une dépense qu'il a en attente ou en conflit.
                'cle' => 'expenses',
                'requete' => fn () => \App\Models\Expense::query()
                    ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
                    ->select(['id', 'expense_date', 'label', 'category', 'amount', 'treasury_account_id', 'is_active',
                        'status', 'accounting_entry_id', 'payment_mode', 'cost_center_id', 'supplier_id', 'beneficiary',
                        'created_by', 'on_credit', 'updated_at']),
                'historique' => fn ($q) => $q->orderBy('expense_date')->orderBy('id'),
                'enJson' => fn (\App\Models\Expense $d) => [
                    'id' => $d->id,
                    'expense_date' => $d->expense_date?->format('Y-m-d'),
                    'label' => $d->label,
                    'category' => $d->category,
                    'amount' => (float) $d->amount,
                    'treasury_account_id' => $d->treasury_account_id,
                    'is_active' => (bool) $d->is_active,
                    // Ticket U14 — le badge et le filtre « Statut » du Blade (`payee` / `en_attente`), et la règle de
                    // modification d'une dépense COMPTABILISÉE, que le poste applique avant d'écrire (`SaisieDepenseAction`).
                    'status' => $d->status,
                    'accounting_entry_id' => $d->accounting_entry_id,
                    // Ticket DEP3 — l'en-tête d'une dépense à plusieurs lignes (le total reste `amount`, le résumé `label`).
                    'payment_mode' => $d->payment_mode,
                    'cost_center_id' => $d->cost_center_id,
                    'supplier_id' => $d->supplier_id,
                    'beneficiary' => $d->beneficiary,
                    'created_by' => $d->created_by,
                    // Ticket DEP7 — dépense À CRÉDIT (crédite le 401, aucune trésorerie : `treasury_account_id` nul) ; sa dette
                    // descend avec `payables`.
                    'on_credit' => (bool) $d->on_credit,
                    'updated_at' => $d->updated_at?->toIso8601String(),
                ],
                'lignes' => [
                    // 🔴→✅ TICKET DEP3 — LES LIGNES DES DÉPENSES SERVIES DESCENDENT AVEC ELLES, au même curseur : TOUTES les
                    // lignes de chaque dépense servie (une dépense modifiée renvoie la liste COMPLÈTE de ses lignes : le
                    // poste remplace celles qu'il tient), JAMAIS une ligne d'une dépense non servie. Même patron que
                    // `purchase_lines`. Le poste n'a pas à recalculer le total : `expenses.amount` en est la somme.
                    'expense_lines' => ['expense_id', fn (Collection $ids) => $this->lignesDesPieces(
                        \App\Models\ExpenseLine::class,
                        'expense_id',
                        $ids,
                        fn ($ligne) => [
                            'id' => $ligne->id,
                            'expense_id' => $ligne->expense_id,
                            'position' => (int) $ligne->position,
                            'label' => $ligne->label,
                            'charge_account_id' => $ligne->charge_account_id,
                            'amount' => (float) $ligne->amount,
                        ],
                        'position',   // l'ordre de saisie des lignes, pas celui de leur création (même seconde)
                    )],
                ],
            ],
            [
                // 🔴→✅ TICKET U13 — LA PAIE RÉGLÉE DESCEND AU POSTE, RÉDUITE À CE QUE LE RAPPORT LIT.
                //
                // `RecettesDepenses::depensesRows()` compte la paie (`payslips`) dans les sorties : le poste, qui ne
                // l'avait pas, donnait un total des dépenses faux. ⚠️⚠️ SALAIRES (ticket S3) : seules les colonnes du
                // calcul du web descendent — l'instant du règlement (`created_at`, en HEURE MURALE du serveur
                // 'Y-m-d H:i:s' : le rapport prend son JOUR, `toDateString()`), le NOM de l'employé (« Nom Prénom »,
                // `null` sans employé) et le NET versé. Jamais le brut, les retenues (CNSS, ITS, absences), les charges
                // patronales, la période ni l'identifiant de l'employé ; servie aux seuls comptes `view-rapports` (voir
                // [PERMISSIONS_DE_TIRAGE]). Table d'historique (un bulletin par employé et par mois, jamais modifié) :
                // paginée par pièce au curseur. ⚠️ Le NOM est celui de l'employé AUJOURD'HUI (le web le lit par la
                // relation) : un bulletin dont l'employé a été modifié depuis `since` redescend aussi.
                'cle' => 'payslips',
                'requete' => fn () => \App\Models\Payslip::query()
                    ->with('employee:id,first_name,last_name')
                    ->when($since, fn ($q) => $q->where(fn ($w) => $w->where('updated_at', '>', $since)
                        ->orWhereHas('employee', fn ($e) => $e->where('updated_at', '>', $since))))
                    ->select(['id', 'employee_id', 'net_salary', 'created_at', 'updated_at']),
                'historique' => fn ($q) => $q->orderBy('created_at')->orderBy('id'),
                'enJson' => fn (\App\Models\Payslip $p) => [
                    'id' => $p->id,
                    'employee_name' => $p->employee === null ? null : $p->employee->last_name.' '.$p->employee->first_name,
                    'net_salary' => (float) $p->net_salary,
                    'created_at' => $p->created_at?->format('Y-m-d H:i:s'),
                ],
            ],
            [
                // 🔴→✅ TICKET U9 — LE GRAND LIVRE DES STOCKS (`stock_movements`) DESCEND AU POSTE.
                //
                // Trois écrans du web le lisent et le poste ne pouvait pas les reproduire : « Rotation du Stock »
                // (`StockRotationService` : sorties de vente du mois et soldes reconstruits), « Écarts d'Inventaire »
                // (`GestionStocks::TYPES_ECART_INVENTAIRE` du mois, saisis au web OU sur n'importe quel poste) et le
                // Tableau 3 de la ponte (`EggStockLedgerService` : SRH, OS, Stock Final en plateaux, soldes de FERME).
                //
                // ⚠️⚠️ C'EST UN JOURNAL ÉCRIT PAR LE SERVEUR SEUL : `AdjustStockAction` en est le point de passage unique.
                // Au poste c'est un référentiel en LECTURE SEULE — jamais envoyé, et ignoré (compté) s'il l'était (voir
                // `push`). Un ajustement saisi au poste part dans `stock_adjustments`, que le serveur REJOUE ; le
                // mouvement qui en naît porte `reference_id` = identifiant de la ligne du poste, et c'est lui qui
                // redescend ici.
                //
                // ⚠️ MÊME MÉCANISME QUE LES AUTRES TABLES D'HISTORIQUE (ventes, fiches) : tout au premier tirage, puis au
                // curseur `since` (`updated_at`). Une ligne de quelques champs par vente, achat, ponte ou ajustement : la
                // table croît comme les ventes et les achats réunis, servis de la même façon depuis U4.
                //
                // ⚠️ RECOUVREMENT DE DEUX MINUTES SOUS LE CURSEUR, EN PLUS DE CELUI DE TOUT LE TIRAGE. Le curseur est pris
                // au début du tirage, reculé de `HORIZON_TIRAGE_SECONDES` (voir `pull`) ; un journal immuable n'est jamais
                // resservi par une modification, et une sortie perdue l'est pour toujours (F0.84-bis a rencontré le cas
                // réel sur le journal comptable) : il garde donc une marge plus large, contre une transaction lente à se
                // valider. Les lignes déjà reçues reviennent pendant deux minutes : l'absorbeur du poste remplace par
                // identifiant.
                //
                // ⚠️ COLONNES DU CALCUL ET DE L'AFFICHAGE DU JOURNAL, RIEN D'AUTRE (ni horodatages techniques, ni auteur ;
                // `updated_at` n'est lu que pour le curseur de page de S-T4, jamais servi). `movement_date` est servie en
                // HEURE MURALE du serveur ('Y-m-d H:i:s') : le web compare des JOURS (`whereDate`), et un instant UTC lu
                // par un poste réglé sur un autre fuseau changerait le jour d'un mouvement de fin de soirée — donc le mois
                // d'un écart ou la ligne d'une ponte.
                'cle' => 'stock_movements',
                'requete' => fn () => \App\Models\StockMovement::query()
                    ->when($since, fn ($q) => $q->where('updated_at', '>', $since->copy()->subMinutes(2)))
                    ->select(['id', 'product_id', 'type', 'quantity', 'reference_type', 'reference_id', 'reason',
                        'movement_date', 'updated_at']),
                'historique' => fn ($q) => $q->orderBy('movement_date')->orderBy('id'),
                'enJson' => fn ($m) => [
                    'id' => $m->id,
                    'product_id' => $m->product_id,
                    'type' => $m->type,
                    'quantity' => (float) $m->quantity,
                    'reference_type' => $m->reference_type,
                    'reference_id' => $m->reference_id,
                    'reason' => $m->reason,
                    'movement_date' => $m->movement_date?->format('Y-m-d H:i:s'),
                ],
            ],
            [
                // Ticket 14.83 — le journal comptable (voir `chart_of_accounts`) : les écritures ACTIVES modifiées depuis
                // `since`, avec toutes leurs lignes.
                //
                // ⚠️ Ticket S-T4 — SANS BORNE au début du tirage : une ligne d'écriture ne renvoie qu'à un compte (servi à
                // la page 1, jamais vérifié contre le plan au poste) et la liste des écritures actives
                // (`accounting_entry_ids`) est lue juste après la dernière page du journal. Bornées, les écritures
                // passées pendant un long tirage y figureraient sans avoir été servies : le poste relancerait alors
                // tout le journal (F0.84-bis).
                'cle' => 'accounting_entries',
                'requete' => fn () => AccountingEntry::query()
                    ->where('is_active', true)
                    ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
                    ->select(['id', 'fiscal_year_id', 'entry_date', 'reference', 'source_type', 'is_locked', 'created_at',
                        'updated_at']),
                'historique' => fn ($q) => $q->orderByDesc('entry_date'),
                'sansBorne' => true,
                'enJson' => fn (AccountingEntry $e) => [
                    'id' => $e->id,
                    'fiscal_year_id' => $e->fiscal_year_id,
                    // ⚠️ 'Y-m-d', jamais un instant : meme piege que le pointage.
                    'entry_date' => $e->entry_date?->format('Y-m-d'),
                    // 🔴→✅ TICKET 15.29 — `FinancialReportService::grandLivre` departage deux pieces du
                    // MEME JOUR par `created_at`. Sans lui le poste ne peut pas reproduire l'ordre du
                    // serveur (et donc le solde progressif de chaque ligne). Instant de CREATION : il ne
                    // bouge jamais (≠ `updated_at`, que `updateManual` fait avancer par `touch()`).
                    'created_at' => $e->created_at?->toIso8601String(),
                    'reference' => $e->reference,
                    'source_type' => $e->source_type,
                    'is_locked' => $e->is_locked,
                ],
                'lignes' => [
                    // ⚠️ LES LIGNES SUIVENT LEURS ECRITURES : servir les unes sans les
                    // autres donnerait un journal desequilibre, ou des lignes orphelines
                    // que le poste ne saurait rattacher.
                    // ⚠️ TICKET 15.28-bis : PAR PAQUETS DE 5 000. Un `whereIn` de 33 000 identifiants dépasse la
                    // limite de variables de la requête (SQLite ~32 766 ; MySQL 65 535 placeholders) : le tirage
                    // entier échouait. Le résultat est identique (mêmes lignes, même contenu).
                    'accounting_entry_lines' => ['entry_id', fn (Collection $ids) => $ids->chunk(5_000)->flatMap(
                        fn ($paquet) => AccountingEntryLine::query()
                            ->whereIn('entry_id', $paquet->values())
                            ->get(['id', 'entry_id', 'account_id', 'cost_center_id', 'debit', 'credit'])
                    )->values()],
                ],
            ],
        ];
    }

    /**
     * Ticket U4 (D-U4) — une vente ou un achat « modifié depuis `since` » : la pièce elle-même, OU l'une de ses
     * lignes. Les lignes ne voyageant qu'avec leur pièce, une ligne modifiée seule doit faire redescendre sa pièce.
     */
    private function pieceOuLigneModifiee($requete, $since)
    {
        return $requete->where('updated_at', '>', $since)
            ->orWhereHas('lines', fn ($l) => $l->where('updated_at', '>', $since));
    }

    /**
     * Ticket U4 (D-U4) — TOUTES les lignes des pièces servies, par paquets de 500 identifiants (borne des
     * paramètres liés de SQLite). Lire les lignes par les identifiants DÉJÀ servis, et non par une seconde
     * requête sur le curseur, garantit qu'aucune ligne ne descend sans sa pièce : une vente créée entre les deux
     * requêtes ne descend, avec ses lignes, qu'au tirage suivant.
     *
     * @param  class-string<\Illuminate\Database\Eloquent\Model>  $modele
     */
    private function lignesDesPieces(string $modele, string $cle, Collection $ids, \Closure $enJson, string $ordre = 'created_at'): Collection
    {
        return $ids->chunk(500)
            ->flatMap(fn ($paquet) => $modele::query()
                ->when(method_exists($modele, 'product'), fn ($q) => $q->with('product:id,name'))
                ->whereIn($cle, $paquet->values())
                ->orderBy($ordre)
                ->orderBy('id')
                ->get())
            ->map($enJson)
            ->values();
    }

    /**
     * POST /api/sync/push
     * Corps attendu : { "livestock_daily_entries": [...], "sales": [...], "stock_adjustments": [...] }
     * Chaque table est traitée selon sa propre règle — voir docblock de
     * classe. Retourne, table par table, les id acceptés et les id
     * rejetés (avec motif), jamais un simple "200 OK" muet qui masquerait
     * un rejet silencieux à l'utilisateur Flutter.
     */
    public function push(Request $request): JsonResponse
    {
        // 🔴→✅ TICKET S-T2 — UN POSTE NE SIGNE PAS AU NOM D'UN AUTRE. Le `device_id` envoyé était écrit tel quel sur
        // les avances, règlements, retours, remboursements, imputations et transferts : un poste pouvait les attribuer
        // à un autre. Refusé AVANT tout traitement (rien n'est écrit, rien n'est journalisé).
        if ($refus = $this->refusPosteDifferentDuJeton($request)) {
            return $refus;
        }

        // ⚠️ TICKET 15.26 — UNE CLÉ DONT LA VALEUR N'EST PAS UNE LISTE (`"mails": "x"`) FAISAIT
        // ÉCHOUER TOUT L'ENVOI EN 500 (TypeError sur le paramètre `array` du traitement). Elle est
        // maintenant retirée de la requête AVANT tout traitement et signalée dans `cles_invalides`
        // (clé => motif) ; les autres clés sont traitées normalement.
        $clesInvalides = [];
        foreach (self::CLES_DE_PUSH as $cle) {
            if ($request->has($cle) && ! is_array($request->input($cle))) {
                $request->request->remove($cle);
                $clesInvalides[$cle] = 'La clé « '.$cle.' » doit être une liste d\'enregistrements : elle est ignorée.';
            }
        }

        // 🔴→✅ TICKET 15.50 — UN POSTE QUI N'A PAS VU LA RÉINITIALISATION N'ENVOIE RIEN. Ses données en attente
        // ont été saisies sur une base effacée depuis : les accepter ressusciterait bandes, ventes et écritures
        // (une vente sur un produit au stock remis à 0, une fiche d'une bande disparue). Le poste à jour tire
        // d'abord, voit la marque, purge, puis renvoie la marque qu'il connaît.
        $reinitialisation = CompanySetting::query()->value('data_reset_at');
        if ($reinitialisation !== null) {
            $marque = Carbon::parse($reinitialisation);
            $connue = $request->input('data_reset_at');
            $aJour = is_string($connue) && rescue(
                fn () => Carbon::parse($connue)->equalTo($marque), false, false,
            );

            if (! $aJour) {
                return response()->json([
                    'message' => MotifsRefusPush::reinitialisationNonVue($marque),
                ], 409);
            }
        }

        // 🔴→✅ TICKET S1 — LE RÔLE EST CONTRÔLÉ SUR CHAQUE TABLE ÉCRITE. Ces huit tables étaient acceptées de
        // n'importe quel jeton : un compte caissier pouvait créer des dépenses (trésorerie débitée), des achats,
        // des ajustements de stock ou des pointages. Les enregistrements refusés le sont un par un, avec leur
        // motif, et rejoignent la réponse de leur table après traitement des autres.
        $refusParRole = $this->retirerLesEnvoisSansDroit($request);

        // 🔴→✅ TICKET S-T9 — L'ENVOI EST ATOMIQUE, ET REJOUÉ SUR UN INTERBLOCAGE.
        //
        // Mesuré par l'essai à plusieurs postes, sur MariaDB (jamais vu sur SQLite, qui sérialise tout) : deux comptoirs
        // qui envoient en même temps des ventes de la même bande s'interbloquent (`1213 Deadlock found`, sur la fiche
        // du jour, la bande ou le stock du produit). L'envoi partait en 500 À MOITIÉ ÉCRIT : les fiches de la requête
        // étaient déjà enregistrées, ses ventes non. Le poste renvoyait (S-T1) ; la fiche, désormais connue, ne portait
        // plus les ventes du même envoi (15.30) et chaque vente y comptait ses sujets UNE SECONDE FOIS. Tout l'envoi
        // passe maintenant dans UNE transaction : un échec n'écrit rien, le renvoi retrouve le serveur tel qu'il était.
        // Un interblocage est rejoué jusqu'à trois fois avant de remonter en 500. Ticket S-T13 : par `TransactionRejouable`,
        // le même point que la caisse du web (il remplaçait `DB::transaction(…, 3)`, mêmes règles).
        $result = app(TransactionRejouable::class)->executer(
            fn () => $this->traiterEnvoi($request, $clesInvalides),
            'envoi du poste',
        );

        // 🔴→✅ TICKET S-T13 — LES FACTURES NORMALISÉES DES VENTES REÇUES, APRÈS LA TRANSACTION. L'appel MeCeF était
        // fait DANS la transaction de l'envoi : un envoi rejoué sur interblocage (S-T9) retransmettait au dispositif
        // les ventes de son essai annulé — deux factures pour une vente. Et son `catch (\Throwable)` pouvait avaler un
        // interblocage survenu en écrivant le statut. Une vente reçue est désormais facturée une fois, l'envoi validé.
        foreach ($this->ventesAFacturer as $venteRecue) {
            $facture = app(FacturationMecefService::class)->facturer($venteRecue);

            // 🔴→✅ Ticket U14 — l'échec de la facture d'une vente reçue redevient une ligne du journal d'audit, comme
            // avant S-T13 (qui avait sorti l'appel de la transaction et perdu cette trace) : la vente est gardée, en
            // « Erreur MeCeF », et le journal dit qu'elle vient d'un poste. Libellé dans `AuditLog::ACTION_LABELS`.
            if (! $facture['transmise'] && ! $facture['deja']) {
                AuditLog::record('sale.mecef_failed_on_sync', 'facturation');
            }
        }

        // 🔴→✅ Ticket U13 — ALERTE D'AUTONOMIE ALIMENTAIRE des fiches saisies au poste, comme `saveDay()` au web : APRÈS
        // la validation de l'envoi (comme le web après sa transaction ; un envoi rejoué sur interblocage ne la lève donc
        // qu'une fois), avec les mêmes règles et le même dédoublonnage (`AlerteAutonomieFicheService`). Un échec de la
        // cloche ne fait pas échouer un envoi déjà enregistré : il est signalé au journal des erreurs.
        foreach (array_unique($this->fichesSaisiesAuPoste) as $ficheId) {
            try {
                app(\App\Services\AlerteAutonomieFicheService::class)->apresFicheDuPoste($ficheId);
            } catch (\Throwable $e) {
                report($e);
            }
        }

        foreach ($refusParRole as $table => $refus) {
            $result[$table]['rejected'] = array_merge($result[$table]['rejected'], $refus);
        }

        AuditLog::record('api.sync_push', 'sync', $request->user()->id);
        // Ticket H3 — l'envoi est journalisé par poste, avec ses compteurs acceptés / refusés.
        app(JournalSynchronisationService::class)->envoi($request, $result);

        return response()->json($result);
    }

    /**
     * Ticket S-T9 — le traitement d'un envoi, table par table, dans l'ordre que le poste suppose (voir `push`, qui
     * l'exécute dans une transaction). Rend la réponse, refus par rôle exceptés.
     *
     * @param  array<string, string>  $clesInvalides
     * @return array<string, mixed>
     */
    private function traiterEnvoi(Request $request, array $clesInvalides): array
    {
        $this->fichesPortantLesVentes = [];
        $this->ventesAFacturer = [];
        $this->fichesSaisiesAuPoste = [];

        $result = [
            'cles_invalides' => $clesInvalides,
            // Ticket S-T9 — `merged` : fiche du poste fusionnée dans celle que le serveur tient pour la même (bande, jour).
            'livestock_daily_entries' => ['accepted' => [], 'rejected' => [], 'merged' => []],
            // Ticket BS1 — bandes du poste, rejouées par `SaisieBandeAction` (le point de passage de l'écran web).
            'livestock_lots' => ['accepted' => [], 'rejected' => []],
            // Ticket BS3 — reproducteurs nominatifs du poste, rejoués par `SaisieReproducteurAction` (l'écran web du registre).
            'animals' => ['accepted' => [], 'rejected' => []],
            'sales' => ['accepted' => [], 'rejected' => []],
            // Ticket AV1 — retours et avoirs clients, rejoués par `AvoirClientService` (le point de passage du web).
            'credit_notes' => ['accepted' => [], 'rejected' => []],
            // Ticket ARC2 — demandes de la Corbeille, rejouées par `CorbeilleService` (le point de passage de l'écran web).
            'corbeille_demandes' => ['accepted' => [], 'rejected' => []],
            'stock_adjustments' => ['accepted' => [], 'rejected' => []],
            'veterinary_records' => ['accepted' => [], 'rejected' => []],
            'expenses' => ['accepted' => [], 'rejected' => []],
            'livestock_reproduction_events' => ['accepted' => [], 'rejected' => []],
            'infirmary_records' => ['accepted' => [], 'rejected' => []],
            'veterinary_calendar_events' => ['accepted' => [], 'rejected' => []],
            'purchases' => ['accepted' => [], 'rejected' => []],
            'attendance_records' => ['accepted' => [], 'rejected' => []],
            // Ticket S-T5 — `merged` : créations du poste fusionnées avec une fiche existante (voir `FusionReferentielsService`).
            'products' => ['accepted' => [], 'rejected' => [], 'merged' => []],
            'suppliers' => ['accepted' => [], 'rejected' => [], 'merged' => []],
            'customers' => ['accepted' => [], 'rejected' => [], 'merged' => []],
            'quotes' => ['accepted' => [], 'rejected' => []],
            // Ticket DEV3 — `invoices` : par devis accepté, le lien vers la facture que le serveur vient de créer.
            'quote_conversions' => ['accepted' => [], 'rejected' => [], 'invoices' => []],
            'mails' => ['accepted' => [], 'rejected' => []],
            'archived_documents' => ['accepted' => [], 'rejected' => []],
            'administrative_documents' => ['accepted' => [], 'rejected' => []],
            'supplier_payments' => ['accepted' => [], 'rejected' => []],
            'purchase_returns' => ['accepted' => [], 'rejected' => []],
            'supplier_refunds' => ['accepted' => [], 'rejected' => []],
            'customer_advances' => ['accepted' => [], 'rejected' => []],
            'advance_imputations' => ['accepted' => [], 'rejected' => []],
            'livestock_transfers' => ['accepted' => [], 'rejected' => []],
            'referentiels_ignored' => 0,
        ];

        // Référentiels : le serveur a toujours raison — tout push tenté
        // sur ces tables est explicitement ignoré, jamais silencieusement
        // accepté puis écrasé au pull suivant sans explication.
        // ⚠️ TICKET 14.76 — LA LISTE SUIVAIT LE TIRAGE AVEC DEUX SPRINTS DE
        // RETARD. Les quatre tables clients descendent depuis 14.75/14.76 ;
        // tant qu'elles ne figuraient pas ICI, un envoi les concernant tombait
        // dans le vide SANS ETRE COMPTE — exactement le rejet muet que le
        // commentaire ci-dessus dit refuser. Toute table ajoutee au tirage en
        // lecture seule doit etre ajoutee a cette liste dans le meme ticket.
        foreach ([
            'product_categories',
            'receivables',
            'customer_reminders',
            'purchase_orders',
            'payables',
            'employees',
            'internships',
            'chart_of_accounts',
            'fiscal_years',
            'accounting_entries',
            'accounting_entry_lines',
            'roles',
            'users',
            'audit_logs',
            'notifications',
            'lot_revenues',
            'livestock_species',
            'attestation_templates',
            'attestation_counts',
            // Ticket U2 — servie au tirage depuis D-U2, en lecture seule : le poste ne l'écrit jamais.
            'growth_standards',
            // Ticket U9 — le grand livre des stocks est écrit par le serveur seul (`AdjustStockAction`) : un poste
            // envoie ses ajustements dans `stock_adjustments`, jamais un mouvement.
            'stock_movements',
            // Ticket U13 — la paie se règle au web seul (`GestionPaie::validerReglement`) : servie en lecture seule.
            'payslips',
        ] as $referentialTable) {
            if ($request->has($referentialTable)) {
                $result['referentiels_ignored'] += count($request->input($referentialTable));
            }
        }

        // Ticket H9b (décision D-H9 du 19/10/2026) — PARAMÈTRES ÉLEVAGE MODIFIABLES AU POSTE. Les barèmes cessent d'être
        // des référentiels en lecture seule : rations, prophylaxie, provendes, numérotation et délai de rappel des
        // soins s'envoient avec le droit `manage-elevage` (celui de l'écran web), mêmes validations que
        // `ParametresElevage`, archivage logique, dernier écrivain gagne.
        $parametresElevage = app(\App\Actions\RecordParametresElevageFromDeviceAction::class);
        foreach (\App\Actions\RecordParametresElevageFromDeviceAction::TABLES as $table) {
            if (! $request->has($table)) {
                continue;
            }
            if (! $request->user()?->can('manage-elevage')) {
                $result[$table] = ['accepted' => [], 'rejected' => array_map(
                    fn ($e) => ['id' => is_array($e) ? ($e['id'] ?? null) : null, 'reason' => MotifsRefusPush::roleInsuffisant($table)],
                    $request->input($table),
                )];

                continue;
            }
            $result[$table] = $parametresElevage->execute($table, $request->input($table));
        }

        // Ticket MOD1 — MODULES ACTIFS BASCULABLES AU POSTE (« je n'arrive pas à activer / désactiver les modules »).
        // Droit `manage-modules` (celui de l'écran web `ModulesActifs`), valeur explicite, dernier écrivain gagne.
        if ($request->has('modules_config')) {
            $result['modules_config'] = $request->user()?->can('manage-modules')
                ? app(\App\Actions\RecordModulesConfigFromDeviceAction::class)->execute($request->input('modules_config'), $request->user())
                : ['accepted' => [], 'rejected' => array_map(
                    fn ($e) => ['id' => is_array($e) ? ($e['id'] ?? null) : null, 'reason' => MotifsRefusPush::roleInsuffisant('modules_config')],
                    $request->input('modules_config'),
                )];
        }

        // ⚠️ LES FOURNISSEURS ET LES PRODUITS D'ABORD (15.15, 15.17) : un achat ou un
        // règlement du même envoi peut viser un fournisseur créé au poste à l'instant.
        if ($request->has('suppliers')) {
            $result['suppliers'] = $this->pushSuppliers($request->input('suppliers'), $request->user(), $this->nomDuPoste($request));
        }

        // ⚠️ LES CLIENTS AUSSI D'ABORD (15.18) : une vente ou un règlement du même envoi
        // peut viser un client créé au poste à l'instant.
        if ($request->has('customers')) {
            $result['customers'] = $this->pushCustomers($request->input('customers'), $request->user(), $this->nomDuPoste($request));
        }

        // Ticket DEV — LES DEVIS APRÈS LES CLIENTS : un devis du même envoi peut viser un client créé (ou fusionné) au
        // poste à l'instant. Références traduites comme celles des ventes (`FusionReferentielsService::REFERENCES`).
        if ($request->has('quotes')) {
            $result['quotes'] = $this->pushQuotes($this->envoiTraduit($request, 'quotes'));
        }

        // Ticket DEV3 — LES DEMANDES DE CONVERSION APRÈS LES DEVIS : un poste hors ligne qui crée, envoie, fait accepter
        // puis convertit un devis envoie tout d'un coup ; le devis du même envoi existe donc déjà, au statut `accepte`.
        if ($request->has('quote_conversions')) {
            $result['quote_conversions'] = $this->pushQuoteConversions($request->input('quote_conversions'), $request->user());
        }

        // ⚠️ COURRIERS (15.23) : aucune dépendance, aucun ordre à respecter. `mails` S'ÉCRIT AU
        // POSTE : il n'est donc plus dans la liste des référentiels ignorés ci-dessus.
        if ($request->has('mails')) {
            $result['mails'] = $this->pushMails($request->input('mails'), $request->user());
        }

        // ⚠️ ARCHIVES (15.24) : aucune dépendance, aucun ordre. `archived_documents` S'ÉCRIT AU
        // POSTE : retiré de la liste des référentiels ignorés ci-dessus.
        if ($request->has('archived_documents')) {
            $result['archived_documents'] = $this->pushArchivedDocuments($request->input('archived_documents'), $request->user());
        }

        // ⚠️ DOCUMENTS ADMINISTRATIFS (15.25) : aucune dépendance, aucun ordre. Table écrivable au
        // poste : retirée de la liste des référentiels ignorés ci-dessus.
        if ($request->has('administrative_documents')) {
            $result['administrative_documents'] = $this->pushAdministrativeDocuments($request->input('administrative_documents'), $request->user());
        }

        // ⚠️ APRÈS les clients (15.19) : une avance du même envoi peut viser un client créé au
        // poste à l'instant. `customer_advances` est la CINQUIÈME exception à « référentiel =
        // le serveur gagne » (avec products, suppliers, supplier_payments, customers) : l'argent
        // d'un acompte est reçu au poste, le serveur n'a aucun moyen de le deviner.
        if ($request->has('customer_advances')) {
            $result['customer_advances'] = $this->pushCustomerAdvances(
                $this->envoiTraduit($request, 'customer_advances'),
                $request->user(),
                $request->input('device_id'),
            );
        }

        // ⚠️ LES PRODUITS D'ABORD (15.15) : une vente, un achat ou un ajustement du même
        // envoi peut porter sur un produit créé au poste à l'instant. Traité après,
        // il serait refusé « produit inconnu » alors qu'il est dans le même paquet.
        if ($request->has('products')) {
            $result['products'] = $this->pushProducts($request->input('products'), $request->user(), $this->nomDuPoste($request));
        }

        // 🔴→✅ TICKET U14 — ORDRE DES VERROUS (`OrdreDesVerrous`) : TOUT le stock que l'envoi va mouvementer est verrouillé
        // ICI, par identifiant croissant, AVANT la première fiche. Avant, les fiches (et leur production) passaient
        // d'abord, puis les ventes décrémentaient le stock : l'ordre inverse de la caisse du web (stock, puis fiche),
        // d'où un interblocage croisé possible entre un poste qui envoie et la caisse qui vend dans la même bande. Placé
        // APRÈS les produits du même envoi (créés, ou fusionnés : les références sont déjà traduites).
        OrdreDesVerrous::stock($this->produitsDeLEnvoi($request));

        // Ticket BS1 — LES BANDES AVANT LES FICHES ET LES TRANSFERTS : une fiche, un transfert de constitution du même
        // envoi peut viser la bande que le poste vient de créer.
        if ($request->has('livestock_lots')) {
            $result['livestock_lots'] = $this->pushLots($request->input('livestock_lots'));
        }

        // Ticket BS3 — LES REPRODUCTEURS APRÈS LES BANDES : le sujet d'une bande créée au poste dans le même envoi.
        if ($request->has('animals')) {
            $result['animals'] = $this->pushAnimals($request->input('animals'));
        }

        if ($request->has('livestock_daily_entries')) {
            $result['livestock_daily_entries'] = $this->pushDailyEntries(
                $this->envoiTraduit($request, 'livestock_daily_entries'),
                ! $request->user()?->can('manage-elevage'),
            );
        }

        // Ticket 15.46 — APRÈS les fiches : un transfert reporte ses sujets sur la fiche du jour ; si le poste a
        // créé cette fiche (même envoi), elle doit exister avant, sinon le serveur en créerait une seconde.
        if ($request->has('livestock_transfers')) {
            $result['livestock_transfers'] = $this->pushTransferts(
                $request->input('livestock_transfers'),
                $request->user(),
                $request->input('device_id'),
            );
        }

        if ($request->has('expenses')) {
            $result['expenses'] = $this->pushExpenses($request->input('expenses'));
        }

        if ($request->has('purchases')) {
            $result['purchases'] = $this->pushPurchases($this->envoiTraduit($request, 'purchases'));
        }

        // ⚠️ APRÈS les achats : un règlement peut viser la dette que l'achat du même
        // envoi vient de créer.
        if ($request->has('supplier_payments')) {
            $result['supplier_payments'] = $this->pushSupplierPayments(
                $this->envoiTraduit($request, 'supplier_payments'),
                $request->user(),
                $request->input('device_id'),
            );
        }

        // ⚠️ APRÈS les achats ET les règlements (15.20) : un retour peut viser l'achat du même envoi, et la part non
        // payée de sa dette dépend des règlements déjà passés. Le POSTE N'ENVOIE JAMAIS d'ajustement de stock pour
        // un retour : le serveur décrémente (voir `pushStockAdjustments`).
        if ($request->has('purchase_returns')) {
            $result['purchase_returns'] = $this->pushPurchaseReturns(
                $request->input('purchase_returns'),
                $request->user(),
                $request->input('device_id'),
            );
        }

        // ⚠️ APRÈS les retours (15.20) : un remboursement peut viser la créance que le retour du même envoi vient d'ouvrir.
        if ($request->has('supplier_refunds')) {
            $result['supplier_refunds'] = $this->pushSupplierRefunds(
                $this->envoiTraduit($request, 'supplier_refunds'),
                $request->user(),
                $request->input('device_id'),
            );
        }

        if ($request->has('attendance_records')) {
            $result['attendance_records'] = $this->pushAttendance($request->input('attendance_records'));
        }

        if ($request->has('sales')) {
            // ⚠️ 15.30 : les fiches ACCEPTÉES de ce même envoi sont transmises aux ventes, pour que
            // la vente ne rajoute pas sur une fiche ce que cette fiche porte déjà (double comptage).
            $result['sales'] = $this->pushSales(
                $this->envoiTraduit($request, 'sales'),
                $this->fichesPortantLesVentes,
            );
        }

        // 🔴→✅ TICKET AV1 — APRÈS les ventes : un retour peut viser la vente du même envoi. Le POSTE N'ENVOIE JAMAIS
        // d'ajustement de stock ni d'écriture pour un retour : le serveur réintègre le stock (décision « réintégré ») et
        // passe l'écriture inverse, dans `AvoirClientService`, comme `RetoursAvoirs::saveReturn()`.
        if ($request->has('credit_notes')) {
            $result['credit_notes'] = $this->pushCreditNotes(
                $request->input('credit_notes'),
                $request->user(),
            );
        }

        // ⚠️ APRÈS les ventes ET les avances (15.19) : une imputation peut viser la créance que la
        // vente à crédit du même envoi vient de créer, avec l'avance du même envoi.
        if ($request->has('advance_imputations')) {
            $result['advance_imputations'] = $this->pushAdvanceImputations(
                $request->input('advance_imputations'),
                $request->user(),
                $request->input('device_id'),
            );
        }

        if ($request->has('livestock_reproduction_events')) {
            $result['livestock_reproduction_events'] =
                $this->pushReproductionEvents($request->input('livestock_reproduction_events'));
        }

        if ($request->has('infirmary_records')) {
            $result['infirmary_records'] = $this->pushInfirmerie($request->input('infirmary_records'));
        }

        if ($request->has('veterinary_calendar_events')) {
            $result['veterinary_calendar_events'] =
                $this->pushCalendrierVeterinaire($request->input('veterinary_calendar_events'));
        }

        if ($request->has('stock_adjustments')) {
            $result['stock_adjustments'] = $this->pushStockAdjustments(
                $this->envoiTraduit($request, 'stock_adjustments'),
                $this->identifiantsDeRetours($request->input('purchase_returns', [])),
            );
        }

        if ($request->has('veterinary_records')) {
            $result['veterinary_records'] = $this->pushVeterinaryRecords($request->input('veterinary_records'));
        }

        // 🔴→✅ TICKET ARC2 — EN DERNIER : une demande de restauration ou de suppression porte sur ce que le même envoi
        // vient d'archiver (le client archivé au poste puis supprimé dans le même paquet). Le POSTE N'ENVOIE QUE LA
        // DEMANDE ; les effets (et leurs refus) sont ceux de `CorbeilleService`, comme la page web.
        if ($request->has('corbeille_demandes')) {
            $result['corbeille_demandes'] = $this->pushCorbeilleDemandes(
                $request->input('corbeille_demandes'),
                $request->user(),
                $this->nomDuPoste($request),
            );
        }

        return $result;
    }

    /**
     * Ticket U14 — les produits dont l'envoi peut mouvementer le stock : lignes des ventes et des achats, ajustements,
     * lignes des achats retournés, et ce que les fiches, les ventes et les transferts de bandes font bouger
     * (`OrdreDesVerrous::produitsDesFiches`). Un sur-ensemble ne coûte qu'un verrou de plus ; un oubli rouvrirait
     * l'interblocage croisé.
     *
     * @return array<int, string>
     */
    private function produitsDeLEnvoi(Request $request): array
    {
        $liste = fn (mixed $v): array => is_array($v) ? array_values(array_filter($v, 'is_array')) : [];
        $produits = [];
        $bandes = [];

        foreach (['sales', 'purchases'] as $table) {
            foreach ($liste($this->envoiTraduit($request, $table)) as $piece) {
                foreach ($liste($piece['lines'] ?? null) as $ligne) {
                    $produits[] = $ligne['product_id'] ?? null;
                    $bandes[] = $ligne['lot_id'] ?? null;
                }
            }
        }
        foreach ($liste($this->envoiTraduit($request, 'stock_adjustments')) as $ajustement) {
            $produits[] = $ajustement['product_id'] ?? null;
        }
        $achatsRetournes = array_filter(array_map(fn ($r) => $r['purchase_id'] ?? null, $liste($request->input('purchase_returns'))), 'is_string');
        if ($achatsRetournes !== []) {
            array_push($produits, ...\App\Models\PurchaseLine::whereIn('purchase_id', $achatsRetournes)->pluck('product_id')->all());
        }
        foreach ($liste($this->envoiTraduit($request, 'livestock_daily_entries')) as $fiche) {
            $bandes[] = $fiche['lot_id'] ?? null;
        }
        foreach ($liste($request->input('livestock_transfers')) as $transfert) {
            $bandes[] = $transfert['source_lot_id'] ?? null;
            $bandes[] = $transfert['target_lot_id'] ?? null;
        }

        return [...$produits, ...OrdreDesVerrous::produitsDesFiches($bandes)];
    }

    /**
     * Ticket S-T5 — les enregistrements d'une table d'envoi, références aux clients, fournisseurs et produits FUSIONNÉS
     * traduites vers l'identifiant du serveur. ⚠️ Appelé pour CHAQUE table de `FusionReferentielsService::REFERENCES`
     * (un garde-fou le vérifie), et APRÈS `pushSuppliers` / `pushCustomers` / `pushProducts` du même envoi : une vente
     * peut viser le client que ce même envoi vient de fusionner.
     */
    private function envoiTraduit(Request $request, string $table): mixed
    {
        return app(FusionReferentielsService::class)->traduireEnvoi($table, $request->input($table));
    }

    /** Ticket S-T5 — le poste qui parle : nom de son jeton Sanctum (S-T2), sinon le `device_id` envoyé. */
    private function nomDuPoste(Request $request): ?string
    {
        $jeton = $request->user()?->currentAccessToken();
        if ($jeton instanceof PersonalAccessToken && is_string($jeton->getAttribute('name')) && $jeton->getAttribute('name') !== '') {
            return $jeton->getAttribute('name');
        }
        $envoye = $request->input('device_id');

        return is_string($envoye) && $envoye !== '' ? Str::limit($envoye, 250, '') : null;
    }

    /**
     * Ticket S1 — permission exigée pour écrire chaque table par le poste, identique à celle de l'écran web
     * correspondant (`$this->authorize()` des composants Livewire). Les autres tables écrivables contrôlent
     * déjà le rôle dans leur propre traitement.
     */
    private const PERMISSION_PAR_TABLE = [
        'livestock_daily_entries' => 'manage-elevage',
        // Ticket BS1 — le droit de l'écran « Bandes & Sujets » du web.
        'livestock_lots' => 'manage-elevage',
        // Ticket BS3 — le droit de l'écran « Registre des Reproducteurs » du web.
        'animals' => 'manage-elevage',
        'livestock_transfers' => 'manage-elevage',
        'livestock_reproduction_events' => 'manage-elevage',
        'infirmary_records' => 'manage-elevage',
        'veterinary_calendar_events' => 'manage-elevage',
        'veterinary_records' => 'manage-elevage',
        'expenses' => 'manage-achats',
        'purchases' => 'manage-achats',
        'attendance_records' => 'manage-rh',
        'sales' => 'manage-ventes',
        // Ticket DEV — le droit du composant `Ventes\Devis` du web.
        'quotes' => 'manage-ventes',
        // Ticket AV1 — le droit de `RetoursAvoirs::saveReturn()` / `markAsTreated()` du web.
        'credit_notes' => 'manage-ventes',
        // Ticket ARC2 — le droit de l'écran Corbeille du web (administrateur).
        'corbeille_demandes' => 'manage-parametres',
        'stock_adjustments' => 'manage-stocks',
    ];

    /**
     * Ticket S-T2 (méthode TATACORA) — le `device_id` envoyé doit être le NOM DU JETON Sanctum courant : le jeton est
     * délivré au poste à la connexion (`AuthController::login`, nommé d'après `device_name`), et c'est lui seul qui
     * dit quel poste parle. Refus 403, avec un motif français, sinon. Le journal de synchronisation (H3) lit déjà le
     * nom du jeton, jamais la valeur envoyée.
     *
     * ⚠️ PORTÉE : la vérification s'applique quand le jeton est un vrai jeton de poste — une ligne de
     * `personal_access_tokens` portant un nom. Un jeton transitoire (`Sanctum::actingAs`, `actingAs($u, 'sanctum')`
     * des tests, session web d'un `TransientToken`) ne nomme aucun poste : il n'y a rien à comparer. Un `device_id`
     * absent ou vide n'est pas comparé non plus (rien n'est signé au nom de personne ; les enregistrements gardent
     * le leur).
     */
    private function refusPosteDifferentDuJeton(Request $request): ?JsonResponse
    {
        $envoye = $request->input('device_id');
        if (! is_string($envoye) || $envoye === '') {
            return null;
        }

        $jeton = $request->user()?->currentAccessToken();
        if (! $jeton instanceof PersonalAccessToken || ! $jeton->exists) {
            return null;
        }

        $nom = $jeton->getAttribute('name');
        if (! is_string($nom) || $nom === '' || hash_equals($nom, $envoye)) {
            return null;
        }

        return response()->json(['message' => MotifsRefusPush::posteDifferentDuJeton($envoye, $nom)], 403);
    }

    /**
     * Ticket S1 — retire de la requête les enregistrements que le rôle de l'utilisateur ne permet pas d'écrire,
     * et renvoie leurs refus motivés, table par table.
     *
     * ⚠️ Le poste inscrit chaque vente de bétail dans la fiche du jour (`vente`) et renvoie cette fiche avec
     * la vente : un compte `manage-ventes` passe donc ce filtre pour les fiches, et `pushDailyEntries` ne lui
     * laisse modifier que la vente.
     *
     * @return array<string, array<int, array{id?: mixed, client_ref?: mixed, reason: string}>>
     */
    private function retirerLesEnvoisSansDroit(Request $request): array
    {
        $utilisateur = $request->user();
        $refus = [];

        foreach (self::PERMISSION_PAR_TABLE as $table => $permission) {
            $envois = $request->input($table);

            if (! is_array($envois) || ($utilisateur && $utilisateur->can($permission))) {
                continue;
            }

            // Les fiches d'un compte de vente sont jugées une par une dans `pushDailyEntries` : il peut y
            // inscrire la vente, rien d'autre.
            if ($table === 'livestock_daily_entries' && $utilisateur && $utilisateur->can('manage-ventes')) {
                continue;
            }

            $autorises = [];
            foreach ($envois as $envoi) {
                $cle = $table === 'stock_adjustments' ? 'client_ref' : 'id';
                $refus[$table][] = [
                    $cle => is_array($envoi) ? ($envoi[$cle] ?? null) : null,
                    'reason' => MotifsRefusPush::roleInsuffisant($table),
                ];
            }

            $request->merge([$table => $autorises]);
        }

        return $refus;
    }

    /**
     * Ticket 15.38 — colonnes de saisie de `livestock_daily_entries` NOT NULL (DEFAULT 0) en base alors que la
     * validation les déclare `nullable`. Mesure : un `null` y donnait `NOT NULL constraint failed` -> HTTP 500 pour
     * TOUT l'envoi. `don` (NULLABLE en base) n'en fait pas partie : son `null` est une vraie valeur.
     */
    private const FICHE_COLONNES_NOT_NULL = ['achat', 'ne', 'mort', 'vente'];

    /**
     * Ticket 15.38 — un `null` sur une colonne NOT NULL à valeur par défaut est traité comme une clé ABSENTE : la
     * colonne n'est pas réécrite (valeur existante conservée, ou défaut 0 à la création). C'est le comportement
     * déjà en vigueur pour une clé omise ; aucune règle métier nouvelle. Conséquence voulue pour le garde-fou 15.34 :
     * une fiche qui ne porte que des `null` sur ces colonnes est « sans colonne de saisie ».
     *
     * @param  array<string, mixed>  $donnees
     * @param  array<int, string>  $colonnes
     * @return array<string, mixed>
     */
    private function sansNullSurColonnesNotNull(mixed $donnees, array $colonnes): mixed
    {
        if (! is_array($donnees)) {
            return $donnees;
        }

        foreach ($colonnes as $colonne) {
            if (array_key_exists($colonne, $donnees) && $donnees[$colonne] === null) {
                unset($donnees[$colonne]);
            }
        }

        return $donnees;
    }

    /**
     * Ticket 15.40 — colonnes de VENTILATION PAR CATÉGORIE (10 colonnes `unsignedInteger` NULLABLES, ticket 15.39).
     * `null` y veut dire « non ventilé / inconnu » en base ; dans le PUSH, un `null` est traité comme une clé ABSENTE
     * (même règle que 15.38) : il n'efface pas une ventilation déjà saisie et ne fait pas une « saisie » (15.34).
     */
    private const FICHE_COLONNES_VENTILATION = [
        'mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune',
        'passage_sevre_jeune', 'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune',
    ];

    /** Ticket 15.40 — effectifs par catégorie DÉRIVÉS (comme `effectif_final`) : jamais saisis sur une bande à chaîne. */
    private const FICHE_CATEGORIES_DERIVEES = ['cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune'];

    /** Ticket S-T9 — colonnes de saisie qui ne font pas bouger l'effectif (ponte, aliment, pesée, effectifs saisis, soin). */
    private const FICHE_COLONNES_SAISIE_LIBRES = [
        'ponte_total', 'ponte_casses', 'feed_qty_kg', 'weight_sample_avg_g', 'effectif_m', 'effectif_f',
        'effectif_sevres', 'effectif_smeres', 'cat_eff_4', 'feed_product_id', 'treatment_product_id', 'treatment_dose',
        'symptomes',
    ];

    /** Ticket 15.40 — colonnes qui font bouger l'effectif : leur présence déclenche le contrôle du passage (D3). */
    private const FICHE_COLONNES_MOUVEMENT = [
        'achat', 'ne', 'mort', 'vente', 'don', 'mort_repro', 'mort_sevre', 'mort_jeune',
        'don_repro', 'don_sevre', 'don_jeune', 'passage_sevre_jeune', 'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune',
    ];

    /**
     * Ticket 15.34 — vrai si la fiche envoyée porte au moins UNE colonne de saisie (clé présente,
     * même nulle ou à zéro). Colonnes de saisie = celles du modèle hors identité de la fiche
     * (`lot_id`, `entry_date`) et hors valeurs DÉRIVÉES : `effectif_final` (toujours recalculé par le serveur)
     * et, depuis 15.40, `cat_eff_repro/sevre/jeune` (dérivés de la chaîne par catégorie, 15.39). Une ventilation
     * ou un départ à valeur NON nulle (même 0) reste une saisie : « connu à zéro » est une information, comme
     * `mort = 0` ; leurs `null` ont été retirés avant (clé absente).
     */
    /**
     * Ticket S1 — la fiche envoyée change-t-elle autre chose que la vente par rapport au serveur ? Une fiche
     * inconnue est comparée aux valeurs par défaut (0 pour achat, ne, mort, don et les mouvements ventilés que
     * la vente pose « connus à zéro », vide pour le reste).
     *
     * @param  array<string, mixed>  $fiche  champs validés
     */
    private function modifieAutreChoseQueLaVente(array $fiche, ?LivestockDailyEntry $existant): bool
    {
        $libres = ['id', 'lot_id', 'entry_date', 'vente', 'vente_sexe', 'vente_montant'];
        $aZeroParDefaut = array_merge(self::FICHE_COLONNES_NOT_NULL, ['don'], self::FICHE_COLONNES_VENTILATION);

        foreach (array_diff_key($fiche, array_flip($libres)) as $colonne => $valeur) {
            $connue = $existant?->getAttribute($colonne);

            if ($existant === null && in_array($colonne, $aZeroParDefaut, true)) {
                $connue = 0;
            }

            $egal = is_numeric($valeur) && is_numeric($connue)
                ? (float) $valeur === (float) $connue
                : ($valeur === null ? $connue === null : (string) $valeur === (string) $connue);

            if (! $egal) {
                return true;
            }
        }

        return false;
    }

    private function porteUneColonneDeSaisie(array $entry): bool
    {
        $colonnes = array_diff(
            (new LivestockDailyEntry())->getFillable(),
            array_merge(['lot_id', 'entry_date', 'effectif_final'], self::FICHE_CATEGORIES_DERIVEES),
        );

        return array_intersect_key($entry, array_flip($colonnes)) !== [];
    }

    /**
     * Ticket 15.40 — CONTRÔLES DE LA VENTILATION PAR CATÉGORIE d'une fiche, sur l'état FUSIONNÉ (fiche existante +
     * valeurs envoyées, `$fiche` ayant déjà reçu `fill()` mais n'étant pas encore enregistrée). Lève une
     * `ValidationException` (motifs en français) ; ne modifie la fiche que pour poser les « zéros connus » et
     * neutraliser les catégories dérivées d'une bande à chaîne.
     *
     * Ordre : (a) départ D4 ; (b) clés de ventilation incomplètes ; (c) bande à chaîne : D7 / zéros connus ;
     * (d) total = somme de la ventilation ; (e) passage D3.
     *
     * @param  array<string, mixed>  $entry  fiche reçue, `null` des 10 colonnes déjà retirés
     */
    private function verifierVentilation(array $entry, LivestockDailyEntry $fiche, ?LivestockDailyEntry $existant): void
    {
        $service = app(EffectifParCategorieService::class);
        $lot = $fiche->lot;
        $jour = $fiche->entry_date->format('Y-m-d');
        $colonnesDepart = ['cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune'];
        $tete = $service->teteDeChaine($fiche->lot_id);

        // (a) DÉPART (D4) : une seule fois par bande, sur une espèce suivie, somme = effectif au début du jour.
        if (array_intersect_key($entry, array_flip($colonnesDepart)) !== []) {
            if ($tete !== null) {
                $identique = $existant !== null && $tete->id === $existant->id
                    && collect($colonnesDepart)->every(fn ($c) => ! array_key_exists($c, $entry) || (int) $entry[$c] === (int) $tete->{$c});

                if (! $identique) {
                    $this->refuserFiche(MotifsRefusPush::departDejaFixe($tete->entry_date->format('d/m/Y')));
                }
            } else {
                if (EffectifParCategorieService::especeDuLot($lot) === null) {
                    $this->refuserFiche(MotifsRefusPush::departEspeceNonPrise());
                }

                $refus = EffectifParCategorieService::verifierDepart([
                    'repro' => $fiche->cat_depart_repro, 'sevre' => $fiche->cat_depart_sevre, 'jeune' => $fiche->cat_depart_jeune,
                ], $fiche->previousEffectif());
                if ($refus !== null) {
                    $this->refuserFiche($refus);
                }
            }
        }

        // Chaîne « en jeu » pour CETTE fiche : un départ complet existe (en base ou posé par cette fiche) à une date
        // antérieure ou égale, sur une espèce suivie. Une fiche antérieure au départ n'est pas dans la chaîne.
        $departCompletIci = $fiche->cat_depart_repro !== null && $fiche->cat_depart_sevre !== null && $fiche->cat_depart_jeune !== null;
        $dateTete = $tete?->entry_date->format('Y-m-d') ?? ($departCompletIci ? $jour : null);
        $dansLaChaine = $dateTete !== null && $jour >= $dateTete && EffectifParCategorieService::especeDuLot($lot) !== null;

        $groupes = ['mort' => 'morts', 'don' => 'dons'];
        $erreurs = [];

        // (b) clés de ventilation : les trois ou aucune.
        foreach ($groupes as $total => $libelle) {
            $presentes = array_filter(["{$total}_repro", "{$total}_sevre", "{$total}_jeune"], fn ($c) => array_key_exists($c, $entry));
            if ($presentes !== [] && count($presentes) < 3) {
                $erreurs[] = MotifsRefusPush::ventilationIncomplete($libelle);
            }
        }
        if ($erreurs !== []) {
            $this->refuserFiche(...$erreurs);
        }

        if ($dansLaChaine) {
            // Les catégories sont DÉRIVÉES ici : ce que le client envoie n'est pas écrit (la cascade les recalcule).
            foreach (self::FICHE_CATEGORIES_DERIVEES as $colonne) {
                $fiche->setAttribute($colonne, $fiche->getOriginal($colonne));
            }

            $aSaisie = $existant === null || $this->porteUneColonneDeSaisie($entry);

            // (c) D7 : des morts/dons non ventilés ne se calculent pas par catégorie. Un total à zéro, lui, est
            // « connu à zéro » dans chaque catégorie (rien d'inventé : trois entiers positifs de somme 0 sont 0).
            foreach ($groupes as $total => $libelle) {
                $colonnes = ["{$total}_repro", "{$total}_sevre", "{$total}_jeune"];
                if (collect($colonnes)->contains(fn ($c) => $fiche->{$c} === null)) {
                    if (array_key_exists($total, $entry) && (int) $fiche->{$total} > 0) {
                        $erreurs[] = MotifsRefusPush::ficheNonVentilee($libelle);
                    } elseif ($aSaisie && (int) $fiche->{$total} === 0) {
                        foreach ($colonnes as $c) {
                            $fiche->{$c} = 0;
                        }
                    }
                }
            }
            if ($erreurs !== []) {
                $this->refuserFiche(...$erreurs);
            }

            // Un passage absent est « connu à zéro » (un ancien poste ne sait pas faire de passage).
            if ($fiche->passage_sevre_jeune === null && $aSaisie) {
                $fiche->passage_sevre_jeune = 0;
            }
        }

        // (d) COHÉRENCE : total = somme des trois catégories, dès que la ventilation est complète (envoyée ou stockée).
        foreach ($groupes as $total => $libelle) {
            $valeurs = array_map(fn ($c) => $fiche->{$c}, ["{$total}_repro", "{$total}_sevre", "{$total}_jeune"]);
            if (! in_array(null, $valeurs, true) && (int) $fiche->{$total} !== array_sum($valeurs)) {
                $erreurs[] = MotifsRefusPush::ventilationIncoherente($libelle, (int) $fiche->{$total}, array_sum($valeurs));
            }
        }
        if ($erreurs !== []) {
            $this->refuserFiche(...$erreurs);
        }

        // (e) PASSAGE DE STADE (D3) : jamais plus que la catégorie source.
        if ($dansLaChaine && array_intersect_key($entry, array_flip(self::FICHE_COLONNES_MOUVEMENT)) !== []) {
            $refus = $service->refusDuPassage($lot, $fiche);
            if ($refus !== null) {
                $this->refuserFiche($refus);
            }
        }
    }

    /** Ticket 15.40 — refus motivé d'une fiche (motifs déjà en français, composés par `MotifsRefusPush::motif`). */
    private function refuserFiche(string ...$motifs): never
    {
        throw ValidationException::withMessages(['ventilation' => array_values($motifs)]);
    }

    /**
     * Fiches élevage : dernier écrivain gagne. `id` fourni par le client
     * (UUID généré côté Flutter à la création, jamais régénéré) — upsert
     * réel, pas de doublon possible.
     *
     * 🔴→✅ TICKET 15.40 — ventilation par catégorie, cohérence, cascade :
     *  - les fiches sont TRAITÉES dans l'ordre (bande, jour) — chaque total de départ (D4) et chaque passage (D3) se
     *    jugent alors sur des fiches antérieures du même envoi déjà écrites ; la RÉPONSE garde l'ordre d'envoi ;
     *  - UNE cascade par bande en fin de lot (à partir du plus ancien jour accepté) : totaux, catégories et
     *    `livestock_lots.current_quantity` des fiches suivantes — ce qui referme le point ouvert de 15.31 (une fiche
     *    poussée sur un jour antérieur ne déclenchait pas la cascade).
     */
    /**
     * @param  bool  $venteSeulement  ticket S1 — compte de vente sans `manage-elevage` : seule la vente de la fiche
     *                                 peut différer de ce que le serveur connaît (voir `modifieAutreChoseQueLaVente`).
     */
    private function pushDailyEntries(array $entries, bool $venteSeulement = false): array
    {
        $entries = array_values($entries);
        $issues = [];
        $cascades = [];
        $saisieDeLEleveur = [];

        // Ordre de traitement : (bande, jour, rang d'envoi). Les éléments illisibles passent en tête et échoueront
        // à la validation, comme avant.
        $ordre = array_keys($entries);
        usort($ordre, function (int $a, int $b) use ($entries) {
            $cle = fn ($e) => is_array($e) ? [(string) ($e['lot_id'] ?? ''), (string) ($e['entry_date'] ?? '')] : ['', ''];

            return [$cle($entries[$a]), $a] <=> [$cle($entries[$b]), $b];
        });

        foreach ($ordre as $rang) {
            $entry = $entries[$rang];

            // ⚠️⚠️ TICKET 15.38 — `null` SUR UNE COLONNE NOT NULL = « CHAMP ABSENT ». Voir `sansNullSurColonnesNotNull`.
            // Ticket 15.40 : même règle pour les 10 colonnes de ventilation (nullables en base, mais `null` = inconnu
            // ne s'« envoie » pas : il n'efface rien et ne fait pas une saisie).
            $entry = $this->sansNullSurColonnesNotNull(
                $entry,
                array_merge(self::FICHE_COLONNES_NOT_NULL, self::FICHE_COLONNES_VENTILATION),
            );

            try {
                // ⚠️⚠️ TICKET 14.69 — BORNES AJOUTEES. Le validateur ne
                // controlait que `id`, `lot_id` et `entry_date` : TOUT LE RESTE
                // passait par `fill()` sans le moindre examen. Un `achat` de
                // -50 gonflait l'effectif, une date d'entree dans dix ans
                // faussait l'effectif de depart de tous les jours suivants.
                $validated = validator($entry, [
                    'id' => ['required', 'uuid'],
                    'lot_id' => ['required', 'uuid', 'exists:livestock_lots,id'],
                    // ⚠️ PAS DE FICHE DANS LE FUTUR : une fiche datee de demain
                    // deviendrait « le jour precedent » de rien, et son effectif
                    // final servirait de point de depart a une journee qui n'a
                    // pas eu lieu.
                    'entry_date' => ['required', 'date', 'before_or_equal:today'],
                    'achat' => ['nullable', 'integer', 'min:0'],
                    'ne' => ['nullable', 'integer', 'min:0'],
                    'mort' => ['nullable', 'integer', 'min:0'],
                    'vente' => ['nullable', 'integer', 'min:0'],
                    'don' => ['nullable', 'integer', 'min:0'],
                    'ponte_total' => ['nullable', 'integer', 'min:0'],
                    'ponte_casses' => ['nullable', 'integer', 'min:0'],
                    'feed_qty_kg' => ['nullable', 'numeric', 'min:0'],
                    'weight_sample_avg_g' => ['nullable', 'numeric', 'min:0'],
                    // Ticket 15.40 — ventilation par catégorie : MÊME règle que les autres quantités de la fiche
                    // (entier >= 0, aucun plafond — les colonnes existantes n'en ont pas).
                    'mort_repro' => ['nullable', 'integer', 'min:0'],
                    'mort_sevre' => ['nullable', 'integer', 'min:0'],
                    'mort_jeune' => ['nullable', 'integer', 'min:0'],
                    'don_repro' => ['nullable', 'integer', 'min:0'],
                    'don_sevre' => ['nullable', 'integer', 'min:0'],
                    'don_jeune' => ['nullable', 'integer', 'min:0'],
                    'passage_sevre_jeune' => ['nullable', 'integer', 'min:0'],
                    'cat_depart_repro' => ['nullable', 'integer', 'min:0'],
                    'cat_depart_sevre' => ['nullable', 'integer', 'min:0'],
                    'cat_depart_jeune' => ['nullable', 'integer', 'min:0'],
                    // 🔴→✅ TICKET S1 — colonnes que `fill()` écrivait SANS contrôle : effectifs négatifs, produit
                    // inexistant (violation de clé étrangère, donc erreur 500 pour tout l'envoi), sexe hors liste.
                    'effectif_m' => ['nullable', 'integer', 'min:0'],
                    'effectif_f' => ['nullable', 'integer', 'min:0'],
                    'effectif_sevres' => ['nullable', 'integer', 'min:0'],
                    'effectif_smeres' => ['nullable', 'integer', 'min:0'],
                    'cat_eff_repro' => ['nullable', 'integer', 'min:0'],
                    'cat_eff_sevre' => ['nullable', 'integer', 'min:0'],
                    'cat_eff_jeune' => ['nullable', 'integer', 'min:0'],
                    'cat_eff_4' => ['nullable', 'integer', 'min:0'],
                    'feed_product_id' => ['nullable', 'uuid', 'exists:products,id'],
                    'treatment_product_id' => ['nullable', 'uuid', 'exists:products,id'],
                    'treatment_dose' => ['nullable', 'string', 'max:100'],
                    'symptomes' => ['nullable', 'string', 'max:5000'],
                    'vente_sexe' => ['nullable', 'in:M,F,Mixte'],
                    'vente_montant' => ['nullable', 'numeric', 'min:0'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                // 🔴→✅ Ticket EX5 (EF5, décision Q3 du 20/10/2026) — une fiche datée dans un exercice CLOS est refusée,
                // avec le motif R4 des fiches du web (`saveDay`) : le stock consommé de l'exercice est figé avec son
                // inventaire. Elle était acceptée (fiche du 22/12/2026 envoyée le 15/03/2027, 2026 clôturé).
                if ($refusExercice = app(\App\Services\AccountingEntryService::class)->refusExerciceClos($validated['entry_date'])) {
                    $issues[$rang] = ['ko' => ['id' => $validated['id'], 'reason' => $refusExercice]];

                    continue;
                }

                // Ticket U13 — une SAISIE de l'éleveur (voir [fichesSaisiesAuPoste]) ?
                $saisieDeLEleveur[$rang] = ! $venteSeulement
                    && (($validated['feed_qty_kg'] ?? null) !== null || $this->modifieAutreChoseQueLaVente($validated, null));

                // ⚠️ 'id' n'est PAS dans $fillable de LivestockDailyEntry
                // (comme la quasi-totalité des modèles de ce projet — id
                // généré par HasUuids, jamais mass-assignable) : le passer
                // dans le tableau d'attributs d'`updateOrCreate()` serait
                // silencieusement ignoré à la création, cassant la
                // garantie "UUID généré côté client jamais régénéré"
                // (LARAVEL_SYNC_FLUTTER.md). Assignation explicite hors
                // mass-assignment, seule façon sûre de préserver l'id
                // client sur une table qui protège volontairement ce
                // champ.
                $existant = LivestockDailyEntry::find($validated['id']);

                // ⚠️⚠️ TICKET 15.34 — GARDE-FOU CONTRE LA FICHE VIDE. Depuis F0.90 le poste renvoie,
                // quand une vente est relancée, la fiche du jour RÉDUITE à `id`, `lot_id`, `entry_date`
                // (aucune colonne de saisie) pour ne pas écraser les corrections faites sur le web. Si
                // cet `id` est INCONNU (fiche disparue après restauration ou intervention en base), la
                // créer donnerait une fiche vide « acceptée » : la vente du même envoi croirait la
                // fiche porteuse de ses N sujets (15.30) et ne les compterait pas — 0 au lieu de N.
                // Refus motivé : la vente, elle, est comptée normalement sur la fiche qu'elle crée.
                // `effectif_final` et `cat_eff_*` ne sont jamais repris du client : ils ne comptent pas comme saisie.
                // Un `id` CONNU n'est pas concerné : `fill()` n'écrit que les champs envoyés.
                if ($existant === null && ! $this->porteUneColonneDeSaisie($entry)) {
                    $issues[$rang] = ['ko' => ['id' => $validated['id'], 'reason' => MotifsRefusPush::ficheReduiteInconnue()]];

                    continue;
                }

                // 🔴→✅ TICKET S1 — un compte de vente inscrit la vente dans la fiche, jamais une saisie d'élevage.
                // Une fiche qui porte autre chose (morts saisis par l'animalier sur le même poste, par exemple)
                // est refusée avec son motif : elle reste sur le poste, sans perte, jusqu'à son envoi par un
                // compte autorisé.
                if ($venteSeulement && $this->modifieAutreChoseQueLaVente($validated, $existant)) {
                    // 🔴→✅ TICKET S-T9 — la fiche NÉE D'UNE VENTE au comptoir (aucune saisie d'élevage : valeurs par
                    // défaut) renvoyée après un accusé perdu, alors que l'animalier y a réuni sa saisie entre-temps :
                    // elle différait du serveur par les morts de l'animalier, et le caissier était refusé pour une
                    // saisie qu'il n'a jamais faite (mesuré par l'essai à plusieurs postes). Rien à y écrire : la vente
                    // appartient au serveur (voir plus bas), la saisie d'élevage à l'animalier.
                    if ($existant !== null && ! $this->modifieAutreChoseQueLaVente($validated, null)) {
                        $issues[$rang] = ['ok' => $validated['id']];

                        continue;
                    }

                    $issues[$rang] = ['ko' => ['id' => $validated['id'], 'reason' => MotifsRefusPush::ficheEleveurRequise()]];

                    continue;
                }

                // 🔴→✅ TICKET S-T9 — (BANDE, JOUR) DÉJÀ TENUE PAR LA FICHE D'UN AUTRE POSTE : FUSION PRUDENTE.
                //
                // Mesuré par l'essai à plusieurs postes : la caisse crée la fiche du jour SOUS SON IDENTIFIANT dès
                // qu'elle vend un sujet (`repercuterVente`), l'animalier crée la sienne pour ses morts et son aliment.
                // Le second arrivé était refusé (« Une fiche existe déjà… ») : sur une journée de vente, TOUTES les
                // fiches de l'animalier restaient au poste, morts et aliment jamais connus du serveur. La fiche est
                // maintenant FUSIONNÉE dans celle du serveur (clé naturelle (bande, jour), comme les référentiels de
                // S-T5 ; réponse `merged`, le poste reprend l'identifiant du serveur) quand l'une des deux ne porte
                // QUE la vente, ou quand elles portent la même saisie (renvoi après un accusé perdu). Deux saisies
                // d'élevage DIFFÉRENTES restent refusées avec leur motif : le choix appartient à l'éleveur.
                $fusionnee = null;
                if ($existant === null) {
                    $occupante = LivestockDailyEntry::where('lot_id', $validated['lot_id'])
                        ->whereDate('entry_date', $validated['entry_date'])->first();
                    if ($occupante !== null) {
                        if (! $this->ficheFusionnable($validated, $occupante)) {
                            $issues[$rang] = ['ko' => ['id' => $validated['id'], 'reason' => MotifsRefusPush::ficheEnDouble()]];

                            continue;
                        }
                        $fusionnee = $occupante;
                    }
                }

                // 🔴→✅ TICKET S-T9 — LA VENTE D'UNE FICHE DÉJÀ CONNUE DU SERVEUR N'EST JAMAIS REPRISE DU POSTE.
                //
                // Mesuré par l'essai : deux caisses vendent chacune un lapin de la même bande le même jour, sur la
                // fiche qu'elles ont toutes deux tirée (vente = v). Chacune renvoie la fiche avec v + 1 ; le serveur
                // écrivait v + 1 deux fois, et exemptait chaque vente de son incrément (15.30) : v + 1 au lieu de v + 2,
                // UN SUJET VENDU JAMAIS SORTI DE LA BANDE. Même perte quand l'animalier renvoie la fiche (vente
                // périmée) après une vente d'un autre poste. La vente d'une fiche existante appartient donc au
                // serveur : chaque vente l'incrémente une fois (idempotence par l'identifiant de la vente), et la fiche
                // du poste ne la remplace plus. Seule une fiche CRÉÉE par cet envoi garde la règle 15.30 (elle porte
                // les ventes du même envoi) ; une vente refusée du même envoi en est alors retirée (`pushSales`), si
                // bien qu'une fiche réduite (F0.90) n'a plus de vente « déjà portée » à protéger.
                $porteLesVentes = $existant === null && $fusionnee === null;
                if ($existant !== null || $fusionnee !== null) {
                    unset($entry['vente'], $validated['vente']);
                }

                if ($fusionnee !== null) {
                    $issues[$rang] = $this->fusionnerFiche($entry, $validated, $fusionnee, $cascades);

                    continue;
                }

                // 🔴→✅ Ticket 15.56 — état AVANT écriture, pour répercuter au stock l'ÉCART des naissances, morts et dons.
                $etatAvant = $existant
                    ? ['ne' => (int) $existant->ne, 'mort' => (int) $existant->mort, 'don' => (int) ($existant->don ?? 0)]
                    : [];

                $record = $existant ?? new LivestockDailyEntry();
                $record->id = $validated['id'];
                // ⚠️⚠️ `effectif_final` N'EST JAMAIS REPRIS DU CLIENT. Le poste
                // le calcule avec l'effectif de la veille **tel qu'il l'avait
                // tire** : si la journee precedente a ete corrigee sur le web
                // depuis, sa valeur est perimee — et elle etait stockee telle
                // quelle, faisant autorite. Le serveur, lui, dispose de toutes
                // les donnees : il recalcule.
                //
                // ⚠️ C'est aussi ce qui fait tenir la borne a zero du ticket
                // 14.63 sur ce chemin : reprendre le nombre du client la
                // contournait entierement.
                // 🔴→✅ TICKET S1 — seules les colonnes VALIDÉES ci-dessus sont reprises (clés présentes dans l'envoi,
                // pour qu'une colonne absente garde sa valeur : comportement 15.38 inchangé).
                $record->fill(Arr::only($entry, array_diff(array_keys($validated), ['id', 'effectif_final'])));

                // Ticket 15.40 — ventilation, cohérence, D4/D7/D3 (lève une ValidationException motivée).
                $this->verifierVentilation($entry, $record, $existant);

                // ⚠️ CALCULE AVANT L'ENREGISTREMENT : la colonne est NOT NULL,
                // et `previousEffectif()` n'a besoin que de `lot_id` et
                // `entry_date`, deja poses par le `fill()` ci-dessus. Un
                // premier `save()` sans effectif echouerait.
                // Ticket 15.46 : transferts entre bandes compris (colonnes dérivées, jamais reprises du poste).
                $record->effectif_final = $record->effectifFinalDepuis($record->previousEffectif());

                $record->save();

                // ⚠️⚠️ TICKET 14.59 — LA PONTE ENTRE RÉELLEMENT AU STOCK.
                // Sans cet appel, une fiche de ponte saisie hors ligne
                // arrivait ici comme une LIGNE MORTE : `ponte_total`
                // renseigné, et pas un seul œuf au stock produits — alors
                // que la maquette annonce « Incrémentation Automatique du
                // Stock : +N Plateaux ». Même défaut que les ventes hors
                // ligne (14.52), même correction : ce que l'écran produit,
                // la synchronisation doit le produire aussi.
                //
                // ⚠️ UNIQUEMENT À LA CRÉATION : un renvoi de la même fiche
                // (poste sans accusé de réception) retrouve
                // l'enregistrement et n'incrémente donc rien deux fois.
                if ($existant === null) {
                    app(RecordEggProductionStockAction::class)->execute($record->fresh());
                }

                // 🔴→✅ Ticket 15.56 — UN DON SAISI AU POSTE SORT DU STOCK. Les fiches du web appellent cette action
                // depuis 14.37 ; la synchronisation ne l'appelait pas : naissances, morts et dons saisis hors ligne
                // ne touchaient jamais le stock du produit de la bande. Calcul par écart : un renvoi n'ajoute rien.
                app(SyncLotProductionStockAction::class)->execute($record->fresh(), $etatAvant);

                $issues[$rang] = ['ok' => $validated['id']];
                if ($porteLesVentes) {
                    $this->fichesPortantLesVentes[$record->lot_id.'|'.$record->entry_date->format('Y-m-d')] = true;
                }

                // Cascade de fin de lot : le plus ancien jour accepté de chaque bande.
                $jour = $record->entry_date->format('Y-m-d');
                if (! isset($cascades[$record->lot_id]) || $jour < $cascades[$record->lot_id]) {
                    $cascades[$record->lot_id] = $jour;
                }
            } catch (ValidationException $e) {
                $issues[$rang] = ['ko' => ['id' => $entry['id'] ?? null, 'reason' => MotifsRefusPush::motif($e)]];
            } catch (\Illuminate\Database\UniqueConstraintViolationException $e) {
                // ⚠️⚠️ DEUX POSTES, LE MEME JOUR, LA MEME BANDE. La table porte
                // `unique(lot_id, entry_date)` ; chaque poste ayant genere SON
                // uuid, l'insertion violait la contrainte. Seule
                // `ValidationException` etait rattrapee : l'exception partait
                // donc en 500 pour la requete ENTIERE, emportant les ventes et
                // les depenses du meme envoi.
                //
                // ⚠️ REFUS CIBLE AVEC SON MOTIF : le poste enregistre alors un
                // CONFLIT (`sync_conflicts`) et cesse de rejouer indefiniment.
                // C'est exactement l'usage de ce mecanisme.
                //
                // 🔴→✅ Ticket S-T9 — DEUX ENVOIS SIMULTANÉS de la même (bande, jour) (mesuré par l'essai à plusieurs
                // postes : deux comptoirs qui vendent dans la même bande et envoient à la même seconde) : le second ne
                // voyait pas encore la fiche du premier à sa lecture et butait sur la contrainte. La fiche est relue,
                // et la fusion prudente s'applique comme si elle avait été vue ; sinon, refus motivé.
                //
                // 🔴→✅ Ticket S-T12 (essai à plusieurs postes, graine 5, MariaDB) — RELUE SOUS VERROU. Une lecture
                // ordinaire, dans cette transaction, lit l'instantané pris à sa première lecture (REPEATABLE READ) : la
                // fiche que l'autre envoi vient de valider y est INVISIBLE, la relecture rendait « aucune », et la fiche
                // de la caisse — qui ne portait que sa vente — était refusée « en double ». La lecture verrouillante lit
                // la dernière version validée.
                $occupante = isset($validated)
                    ? LivestockDailyEntry::where('lot_id', $validated['lot_id'])->whereDate('entry_date', $validated['entry_date'])->lockForUpdate()->first()
                    : null;
                try {
                    $issues[$rang] = $occupante !== null && $this->ficheFusionnable($validated, $occupante)
                        ? $this->fusionnerFiche($entry, $validated, $occupante, $cascades)
                        : ['ko' => ['id' => $entry['id'] ?? null, 'reason' => MotifsRefusPush::ficheEnDouble()]];
                } catch (ValidationException $e) {
                    $issues[$rang] = ['ko' => ['id' => $entry['id'] ?? null, 'reason' => MotifsRefusPush::motif($e)]];
                }
            }
        }

        // 🔴→✅ TICKET 15.40 — UNE cascade par bande, en fin de lot, triée par bande (déterministe).
        ksort($cascades);
        foreach ($cascades as $lotId => $apresDate) {
            app(RecordSaleOnFicheElevageAction::class)->recalculerEnCascade($lotId, $apresDate);
        }

        // La réponse garde l'ORDRE D'ENVOI, quel qu'ait été l'ordre de traitement.
        ksort($issues);
        $accepted = [];
        $rejected = [];
        $merged = [];
        foreach ($issues as $rang => $issue) {
            if (isset($issue['ok'])) {
                $accepted[] = $issue['ok'];
                if (isset($issue['fusion'])) {
                    $merged[] = ['id' => $issue['ok'], 'id_serveur' => $issue['fusion'], 'motif' => MotifsRefusPush::ficheFusionnee()];
                }
                if ($saisieDeLEleveur[$rang] ?? false) {
                    $this->fichesSaisiesAuPoste[] = $issue['fusion'] ?? $issue['ok'];
                }
            } else {
                $rejected[] = $issue['ko'];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected, 'merged' => $merged];
    }

    /**
     * Ticket S-T9 — (bande, jour) des fiches de CET envoi qui portent déjà les ventes du même envoi (règle 15.30) :
     * fiches CRÉÉES par l'envoi, et fiches réduites (sans `vente`, F0.90). Une fiche existante renvoyée avec sa
     * vente, ou fusionnée, n'en fait pas partie : sa vente appartient au serveur, chaque vente l'incrémente.
     *
     * @var array<string, true>
     */
    private array $fichesPortantLesVentes = [];

    /**
     * Ticket S-T13 — ventes INSÉRÉES par l'envoi, facturées au MeCeF une fois sa transaction validée (`push`). Vidée
     * au début de chaque essai : celles d'un essai annulé n'existent plus.
     *
     * @var array<int, string>
     */
    private array $ventesAFacturer = [];

    /**
     * Ticket U13 — identifiants (au SERVEUR : celui de la fiche occupante après une fusion S-T9) des fiches ACCEPTÉES
     * de cet envoi qui sont une SAISIE de l'éleveur — l'équivalent d'un `saveDay()` du web : compte `manage-elevage`
     * (la permission de `saveDay`) et fiche qui porte une provende (`feed_qty_kg`, que la fiche du poste écrit comme
     * celle du web) ou un mouvement d'élevage. Une fiche née d'une vente au comptoir n'en est pas (la caisse du web ne
     * lève pas l'alerte), ni une fiche réduite à son identité (F0.90).
     *
     * @var list<string>
     */
    private array $fichesSaisiesAuPoste = [];

    /**
     * Ticket S-T9 — FUSION de la fiche d'un poste dans [occupante], la fiche que le serveur tient déjà pour la même
     * (bande, jour) ([ficheFusionnable] a dit oui). La saisie d'élevage n'est reprise que si l'occupante n'en porte pas
     * (sinon les deux sont identiques, ou l'envoi n'en porte pas) ; la vente ne l'est jamais. L'occupante est toujours
     * redatée : le poste ne la connaît pas encore, le tirage suivant doit la lui servir.
     *
     * @param  array<string, mixed>  $entry  envoi (sans `vente`)
     * @param  array<string, mixed>  $validated  champs validés (sans `vente`)
     * @param  array<string, string>  $cascades
     * @return array{ok: string, fusion: string}
     */
    private function fusionnerFiche(array $entry, array $validated, LivestockDailyEntry $occupante, array &$cascades): array
    {
        unset($entry['vente'], $validated['vente']);
        $sansSaisie = ! $this->modifieAutreChoseQueLaVente($validated, null)
            || ! $this->modifieAutreChoseQueLaVente($validated, $occupante);
        $etatAvant = ['ne' => (int) $occupante->ne, 'mort' => (int) $occupante->mort, 'don' => (int) ($occupante->don ?? 0)];

        if (! $sansSaisie) {
            $occupante->fill(Arr::only($entry, array_diff(array_keys($validated), ['id', 'lot_id', 'entry_date', 'effectif_final'])));
            $this->verifierVentilation($entry, $occupante, $occupante);
            $occupante->effectif_final = $occupante->effectifFinalDepuis($occupante->previousEffectif());
        }
        $occupante->updated_at = now();
        $occupante->save();

        if (! $sansSaisie) {
            if (! \App\Models\StockMovement::where('reference_type', 'daily_entry')->where('reference_id', $occupante->id)->exists()) {
                app(RecordEggProductionStockAction::class)->execute($occupante->fresh());
            }
            app(SyncLotProductionStockAction::class)->execute($occupante->fresh(), $etatAvant);
        }

        $jour = $occupante->entry_date->format('Y-m-d');
        if (! isset($cascades[$occupante->lot_id]) || $jour < $cascades[$occupante->lot_id]) {
            $cascades[$occupante->lot_id] = $jour;
        }

        return ['ok' => $validated['id'], 'fusion' => $occupante->id];
    }

    /**
     * Ticket S-T9 — la fiche d'un poste peut-elle être FUSIONNÉE dans [occupante], la fiche que le serveur tient
     * déjà pour la même (bande, jour) sous un autre identifiant ? Oui si l'envoi ne porte que la vente (fiche née
     * d'une vente au comptoir), s'il porte exactement la saisie de l'occupante (renvoi après un accusé perdu), ou si
     * l'occupante ne porte que la vente (sa saisie d'élevage vient alors de ce poste). Non quand les deux portent
     * une saisie d'élevage différente : refus motivé, l'éleveur compare.
     *
     * @param  array<string, mixed>  $fiche  champs validés
     */
    private function ficheFusionnable(array $fiche, LivestockDailyEntry $occupante): bool
    {
        if (! $this->modifieAutreChoseQueLaVente($fiche, null) || ! $this->modifieAutreChoseQueLaVente($fiche, $occupante)) {
            return true;
        }

        $colonnes = array_diff(
            array_unique(array_merge(array_keys($fiche), self::FICHE_COLONNES_MOUVEMENT, self::FICHE_COLONNES_SAISIE_LIBRES)),
            self::FICHE_CATEGORIES_DERIVEES,
        );
        // `null` = inconnu, jamais saisi (ventilation d'une bande sans chaîne, ponte d'une bande de chair) : comme dans
        // l'envoi (15.38, 15.40), ce n'est pas une saisie.
        $saisieDeLOccupante = array_filter(
            Arr::only($occupante->getAttributes(), $colonnes),
            fn ($valeur) => $valeur !== null,
        );

        return ! $this->modifieAutreChoseQueLaVente($saisieDeLOccupante, null);
    }

    /**
     * Coherence entre le total annonce et les lignes transmises.
     *
     * ⚠️⚠️ **POURQUOI CE CONTROLE EXISTE.** `RecordSaleAccountingEntryAction`
     * debite `sale->total` et REMET LES LIGNES A L'ECHELLE de ce total pour
     * absorber une remise. C'est juste pour une remise — mais cela signifie
     * qu'un total incoherent produit une ecriture **equilibree et fausse** :
     * les livres enregistrent le montant que le client a annonce, sans que rien
     * ne proteste. Le controle doit donc se faire A LA PORTE, pas dans
     * l'Action.
     *
     * ⚠️ TOLERANCE D'UN CENTIME : les montants transitent en flottants depuis
     * un client Dart. Exiger l'egalite stricte ferait rejeter des ventes
     * parfaitement saines pour un arrondi de representation.
     */
    private function verifierCoherenceDuTotal(array $saleData): void
    {
        $lignes = collect($saleData['lines'] ?? [])
            ->sum(fn ($l) => (float) ($l['manual_total_amount'] ?? 0));

        $remise = (float) ($saleData['discount'] ?? 0);
        $attendu = round($lignes - $remise, 2);
        $annonce = round((float) ($saleData['total'] ?? 0), 2);

        if (abs($attendu - $annonce) < 0.01) {
            return;
        }

        throw ValidationException::withMessages([
            'total' => "Total incoherent : {$annonce} annonce, {$attendu} attendu "
                ."d'apres les lignes (remise de {$remise} deduite).",
        ]);
    }

    /**
     * Saillies declarees au poste — ticket 14.73.
     *
     * ⚠️⚠️ **CREATION SEULE, JAMAIS MISE A JOUR.** Ce canal ouvre la
     * DECLARATION d'une saillie, pas la correction d'un cycle. Une palpation
     * ou une mise bas saisie hors ligne devrait ecraser un enregistrement que
     * le serveur a peut-etre deja fait evoluer : « dernier ecrivain gagne »
     * conviendrait a une fiche journaliere, qui se corrige dans la journee, et
     * pas a un cycle de gestation de trois mois. Le renvoi d'un id deja connu
     * est donc acquitte SANS RIEN REJOUER (idempotence), comme pour les
     * depenses.
     *
     * ⚠️ **DEUX ESPECES SEULEMENT.** L'ecran web ne suit par femelle nommee
     * que la cuniculture et la porciculture : une saillie declaree sur une
     * bande avicole ou helicicole n'aurait aucun ecran pour l'afficher, et
     * fausserait les KPI qui filtrent sur ces deux especes.
     *
     * ⚠️⚠️ **UN SEUL CYCLE EN COURS PAR FEMELLE.** Sans ce garde-fou, deux
     * saillies declarees sur R1 — au poste et au bureau le meme jour, ou deux
     * fois par erreur — produiraient deux gestations concurrentes sur le meme
     * animal. L'ecran les afficherait toutes deux, le KPI « gestantes »
     * compterait double, et rien ne signalerait laquelle est la bonne.
     */
    /**
     * Ticket H8b — ENTRÉES D'INFIRMERIE saisies au poste. Mêmes règles que `SoinsVaccinsHub::saveInfirmaryEntry()`
     * (création, statut initial `en_cours`), `reintegrer()` et `declarerDeces()` (changement de statut d'une entrée
     * connue). Dernier écrivain gagne sur le statut ; la bande, le motif et la date d'entrée ne changent pas après
     * création.
     */
    private function pushInfirmerie(array $entrees): array
    {
        $accepted = [];
        $rejected = [];

        foreach ($entrees as $data) {
            try {
                $existant = isset($data['id']) && is_string($data['id']) ? \App\Models\InfirmaryRecord::find($data['id']) : null;

                if ($existant !== null) {
                    $v = validator($data, [
                        'id' => ['required', 'uuid'],
                        'status' => ['required', 'in:en_cours,reintegre,deces'],
                    ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();
                    if ($existant->status !== $v['status']) {
                        $existant->update(['status' => $v['status']]);
                        AuditLog::record(match ($v['status']) {
                            'reintegre' => 'infirmary_record.reintegrated',
                            'deces' => 'infirmary_record.death_declared',
                            default => 'infirmary_record.created',
                        }, 'elevage');
                    }
                    $accepted[] = $v['id'];

                    continue;
                }

                $v = validator($data, [
                    'id' => ['required', 'uuid'],
                    'lot_id' => ['required', 'uuid', 'exists:livestock_lots,id'],
                    'sujet_ref' => ['nullable', 'string', 'max:50'],
                    'motif' => ['required', 'string', 'max:255'],
                    'isolation_level' => ['required', 'in:Quarantaine stricte,Infirmerie,Simple surveillance'],
                    // Ticket U6 (décision client D-U6 du 19/10/2026) — mêmes règles que `saveInfirmaryEntry()` du web
                    // (`required|date`) : une date FUTURE est acceptée, comme au web. `before_or_equal:today` refusait
                    // ici ce que le web enregistre.
                    'entry_date' => ['required', 'date'],
                    'status' => ['nullable', 'in:en_cours,reintegre,deces'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                $entree = new \App\Models\InfirmaryRecord();
                $entree->id = $v['id'];
                $entree->fill([
                    'lot_id' => $v['lot_id'],
                    'sujet_ref' => ($v['sujet_ref'] ?? null) ?: null,
                    'motif' => $v['motif'],
                    'isolation_level' => $v['isolation_level'],
                    'entry_date' => $v['entry_date'],
                    'status' => $v['status'] ?? 'en_cours',
                ]);
                $entree->save();
                AuditLog::record('infirmary_record.created', 'elevage');
                $accepted[] = $v['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $data['id'] ?? null, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Ticket H8b — INTERVENTIONS PLANIFIÉES au poste (`SoinsVaccinsHub::savePlan()`, statut `planned`) et leur
     * confirmation (`confirmAdministration()`, statut `done`). « En retard » n'est jamais stocké : c'est un affichage
     * (`VeterinaryCalendarEvent::display_status`), il est donc refusé à l'envoi.
     */
    private function pushCalendrierVeterinaire(array $evenements): array
    {
        $accepted = [];
        $rejected = [];

        foreach ($evenements as $data) {
            try {
                $existant = isset($data['id']) && is_string($data['id']) ? \App\Models\VeterinaryCalendarEvent::find($data['id']) : null;

                if ($existant !== null) {
                    $v = validator($data, [
                        'id' => ['required', 'uuid'],
                        'status' => ['required', 'in:planned,done'],
                    ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();
                    if ($existant->status !== $v['status']) {
                        $existant->update(['status' => $v['status']]);
                        AuditLog::record('veterinary_calendar_event.confirmed', 'elevage');
                    }
                    $accepted[] = $v['id'];

                    continue;
                }

                $v = validator($data, [
                    'id' => ['required', 'uuid'],
                    'lot_id' => ['required', 'uuid', 'exists:livestock_lots,id'],
                    'task_type' => ['required', 'string', 'max:100'],
                    'scheduled_date' => ['required', 'date'],
                    'status' => ['nullable', 'in:planned,done'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                $evenement = new \App\Models\VeterinaryCalendarEvent();
                $evenement->id = $v['id'];
                $evenement->fill([
                    'lot_id' => $v['lot_id'],
                    'task_type' => $v['task_type'],
                    'scheduled_date' => $v['scheduled_date'],
                    'status' => $v['status'] ?? 'planned',
                ]);
                $evenement->save();
                AuditLog::record('veterinary_calendar_event.created', 'elevage');
                $accepted[] = $v['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $data['id'] ?? null, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    private function pushReproductionEvents(array $evenements): array
    {
        $accepted = [];
        $rejected = [];

        foreach ($evenements as $data) {
            try {
                $validated = validator($data, [
                    'id' => ['required', 'uuid'],
                    'lot_id' => ['required', 'uuid', 'exists:livestock_lots,id'],
                    'mother_ref' => ['required', 'string', 'max:50'],
                    'sire_ref' => ['nullable', 'string', 'max:50'],
                    // ⚠️ Une saillie datee du futur n'a pas eu lieu.
                    'saillie_date' => ['required', 'date', 'before_or_equal:today'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                // ⚠️ IDEMPOTENCE : deja recue, on acquitte. Ticket H7 — et on applique les ETAPES DU CYCLE saisies au
                // poste (palpation, mise bas, cloture), avec les memes valeurs que les actions de l'ecran web
                // (`SuiviReproduction::recordPalpation`, `saveMiseBas`, `closeCycle`). 🔴 Avant, elles etaient
                // ignorees en silence : le poste croyait sa palpation envoyee, le serveur n'en savait rien.
                // Ticket H7 — étapes du cycle saisies au poste. 🔴→✅ Ticket S-T12 : validées AVANT la création aussi
                // (voir plus bas) — une saillie et sa palpation saisies hors ligne partent dans le même envoi.
                $etapes = validator($data, [
                    'palpation_date' => ['nullable', 'date', 'before_or_equal:today'],
                    'mise_bas_date_actual' => ['nullable', 'date', 'before_or_equal:today'],
                    'nes_vivants' => ['nullable', 'integer', 'min:0'],
                    'nes_morts' => ['nullable', 'integer', 'min:0'],
                    'status' => ['nullable', 'in:en_cours,echec,termine'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();
                // Seules les valeurs RENSEIGNEES s'appliquent : un poste qui ne connait pas une etape ne l'efface pas.
                $maj = array_filter($etapes, fn ($v) => $v !== null);

                $existant = LivestockReproductionEvent::find($validated['id']);
                if ($existant !== null) {
                    if ($maj !== []) {
                        $existant->update($maj);
                        AuditLog::record('reproduction_event.updated_from_device', 'elevage');
                    }
                    $accepted[] = $validated['id'];

                    continue;
                }

                $lot = LivestockLot::with('species')->find($validated['lot_id']);
                $espece = $lot?->species?->code;

                if (! in_array($espece, ['cuniculture', 'porciculture'], true)) {
                    throw ValidationException::withMessages([
                        'lot_id' => "Le suivi par femelle nommee ne couvre que la "
                            ."cuniculture et la porciculture (bande recue : "
                            .($espece ?: 'espece inconnue').").",
                    ]);
                }

                $dejaEnCours = LivestockReproductionEvent::where('lot_id', $validated['lot_id'])
                    ->where('mother_ref', $validated['mother_ref'])
                    ->where('status', 'en_cours')
                    ->exists();

                if ($dejaEnCours) {
                    throw ValidationException::withMessages([
                        'mother_ref' => "Un cycle est deja en cours pour "
                            ."{$validated['mother_ref']} sur cette bande : deux "
                            .'gestations concurrentes sur la meme femelle sont '
                            .'impossibles.',
                    ]);
                }

                $evenement = new LivestockReproductionEvent();
                $evenement->id = $validated['id'];
                $evenement->fill([
                    'lot_id' => $validated['lot_id'],
                    'mother_ref' => $validated['mother_ref'],
                    // ⚠️ `?? null` ET PAS SEULEMENT `?:` : un champ
                    // `nullable` ABSENT du corps ne figure pas dans le
                    // resultat du validateur. Une saillie par insemination —
                    // sans male — faisait donc lever « Undefined array key »,
                    // c'est-a-dire un 500 pour la requete ENTIERE, emportant
                    // les fiches et les ventes du meme envoi.
                    'sire_ref' => ($validated['sire_ref'] ?? null) ?: null,
                    'saillie_date' => $validated['saillie_date'],
                    // Meme etat initial que `SuiviReproduction::saveDeclaration()`.
                    'status' => 'en_cours',
                ]);
                // 🔴→✅ TICKET S-T12 (trouvé par l'essai à plusieurs postes) — LES ÉTAPES SAISIES AVANT LE PREMIER ENVOI.
                // Une saillie déclarée hors ligne, puis palpée (ou mise bas, ou cycle clôturé) avant tout envoi, part en UNE
                // ligne : la création n'en gardait que la saillie, le poste était acquitté, et le tirage suivant écrasait
                // sa palpation par la ligne du serveur — l'étape perdue sans un mot. Elles s'appliquent comme sur un cycle
                // connu (mêmes règles que les actions de l'écran web), dans la même écriture.
                $evenement->fill($maj);
                $evenement->save();
                if (array_diff_key($maj, ['status' => true]) !== [] || ($maj['status'] ?? 'en_cours') !== 'en_cours') {
                    AuditLog::record('reproduction_event.updated_from_device', 'elevage');
                }

                $accepted[] = $validated['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $data['id'] ?? null, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Depenses saisies au poste.
     *
     * ⚠️⚠️ **UNE DEPENSE PORTE DEUX EFFETS, PAS UN.** L'ecran web decaisse la
     * tresorerie ET passe l'ecriture SYSCOHADA (Debit classe 6 / Credit
     * tresorerie). Enregistrer la ligne sans ses effets produirait exactement
     * le defaut deja corrige pour les ventes (14.52) et la ponte (14.59) : un
     * enregistrement qui existe et ne pese sur rien, decouvert des semaines
     * plus tard au rapprochement.
     *
     * ⚠️ **JAMAIS DE MISE A JOUR PAR CE CANAL** : une depense deja decaissee ne
     * se rejoue pas. Un renvoi (poste sans accuse de reception) est un succes
     * silencieux, pas une seconde sortie de caisse.
     */
    /**
     * Achats saisis hors ligne — ticket 14.78.
     *
     * ⚠️⚠️ CREATION SEULEMENT, JAMAIS DE MISE A JOUR. Un achat porte cinq
     * effets (piece et lignes, entree en stock, decaissement, dette, ecriture
     * SYSCOHADA) : rejouer une modification signifierait les defaire, ce que
     * rien ici ne sait faire. Meme regle que les ventes.
     *
     * ⚠️ IDEMPOTENCE PAR L'UUID DU POSTE. Un envoi rejoue — reseau coupe apres
     * traitement, acquittement perdu — ne doit pas entrer la marchandise deux
     * fois au stock ni decaisser deux fois la caisse. C'est exactement le
     * defaut corrige pour les ajustements d'inventaire au ticket 14.74.
     */
    private function pushPurchases(array $purchases): array
    {
        $accepted = [];
        $rejected = [];

        foreach ($purchases as $data) {
            try {
                $validated = validator($data, [
                    'id' => ['required', 'uuid'],
                    'supplier_id' => ['required', 'uuid', 'exists:suppliers,id'],
                    'payment_mode' => ['required', 'in:especes,mobile_money,virement,credit'],
                    'treasury_account_id' => ['required', 'uuid', 'exists:treasury_accounts,id'],
                    'amount_paid' => ['nullable', 'numeric', 'min:0'],
                    // ⚠️ La date de l'achat vient du POSTE : une livraison recue
                    // mardi et synchronisee jeudi appartient a mardi.
                    'purchase_date' => ['nullable', 'date', 'before_or_equal:today'],
                    // Ticket S-T12 — l'INSTANT de l'achat au poste (ISO 8601 avec fuseau) : il date l'entrée en stock.
                    'purchased_at' => ['nullable', 'date'],
                    'lines' => ['required', 'array', 'min:1'],
                    'lines.*.product_id' => ['required', 'uuid', 'exists:products,id'],
                    'lines.*.qty' => ['required', 'numeric', 'min:0.01'],
                    'lines.*.unit_price' => ['required', 'numeric', 'min:0'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                if (Purchase::find($validated['id']) !== null) {
                    $accepted[] = $validated['id'];

                    continue;
                }

                app(RecordPurchaseAction::class)->execute(
                    supplierId: $validated['supplier_id'],
                    lignes: $validated['lines'],
                    paymentMode: $validated['payment_mode'],
                    treasuryAccountId: $validated['treasury_account_id'],
                    montantRegle: (float) ($validated['amount_paid'] ?? 0),
                    purchaseId: $validated['id'],
                    purchaseDate: $validated['purchase_date'] ?? null,
                    instantDuMouvement: $this->instantDeLAchat($validated),
                );

                $accepted[] = $validated['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $data['id'] ?? null, 'reason' => MotifsRefusPush::motif($e)];
            } catch (NoOpenFiscalYearException|ClosedFiscalYearException|\App\Exceptions\AchatNonComptabilisableException $e) {
                // ⚠️⚠️ MEME REGLE QUE LES DEPENSES : un refus comptable rejette
                // CET achat, jamais l'envoi entier. La transaction ayant ete
                // annulee, ni le stock ni la caisse n'ont bouge.
                // Ticket 15.22 : compte manquant / total nul sont refuses de la meme facon (avant : achat accepte sans ecriture).
                $rejected[] = ['id' => $data['id'] ?? null, 'reason' => $e->getMessage()];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * 🔴→✅ Ticket S-T12 — L'ENTRÉE EN STOCK D'UN ACHAT DU POSTE EST DATÉE DE L'ACHAT, plus de sa réception au serveur.
     *
     * Un achat fait mardi matin sur un poste hors ligne, puis un comptage de ces rayons mardi midi au bureau, puis la
     * réception de l'achat jeudi : daté de jeudi, l'achat passait pour POSTÉRIEUR au comptage et la marchandise, déjà
     * comptée, entrait une seconde fois (`InventaireAuComptageService`). Comme une vente (`sold_at`, 15.30), le
     * mouvement porte désormais sa date métier :
     *  - `purchased_at` (instant de la saisie au poste, avec son fuseau) quand il tombe le jour de `purchase_date` —
     *    ramené à l'heure du serveur, jamais dans le futur ;
     *  - sinon, un `purchase_date` passé sans heure connue : le seul JOUR (minuit), placé comme les autres dates seules
     *    (le jour même d'un comptage, il le suit) ;
     *  - sinon (achat du jour d'un poste ancien) : `null`, l'instant de réception, comme avant.
     */
    private function instantDeLAchat(array $valides): ?Carbon
    {
        $jour = $valides['purchase_date'] ?? null;
        $jour = $jour === null ? null : Carbon::parse($jour, config('app.timezone'))->format('Y-m-d');

        if (! empty($valides['purchased_at'])) {
            $instant = Carbon::parse($valides['purchased_at'])->setTimezone(config('app.timezone'));
            if ($instant->greaterThan(now())) {
                $instant = now();
            }
            if ($jour === null || $instant->format('Y-m-d') === $jour) {
                return $instant;
            }
        }

        if ($jour !== null && $jour < now()->format('Y-m-d')) {
            return Carbon::parse($jour, config('app.timezone'))->startOfDay();
        }

        return null;
    }

    /**
     * Pointages saisis hors ligne — ticket 14.81.
     *
     * ⚠️⚠️ L'IDENTITE D'UN POINTAGE N'EST PAS SON UUID, C'EST LE COUPLE
     * (EMPLOYE, JOUR). La table porte `unique(employee_id, attendance_date)`
     * depuis le ticket 8.1 : un employe n'a qu'un pointage par jour. Un simple
     * `insert` echouerait donc des que le web a deja pointe la meme personne le
     * meme matin — et le poste rejouerait indefiniment un envoi rejete.
     *
     * La regle est donc : chercher par le COUPLE, completer s'il existe, creer
     * sinon en conservant l'UUID du poste. C'est aussi ce qui rend l'envoi
     * idempotent — rejouer le meme pointage ne cree pas de doublon.
     *
     * ⚠️ DERNIER ECRIVAIN GAGNE, ASSUME. Si le web a note « present » a 7 h et
     * que le chef d'equipe corrige en « retard » sur le poste, la correction
     * passe : c'est lui qui etait sur place.
     */
    /**
     * Produits créés ou modifiés au poste (ticket 15.15).
     *
     * ⚠️⚠️ SEUL RÉFÉRENTIEL OÙ LE POSTE ÉCRIT, et ce n'est pas une brèche : le serveur
     * garde la main. Il applique les MÊMES règles que la page web
     * (`ProductCatalogService`), exige le droit `manage-stocks`, ENGENDRE le SKU
     * (celui du poste est provisoire, jamais repris) et le rend au tirage suivant.
     *
     * ⚠️ `stock_qty` n'est lu qu'à la CRÉATION. Sur un produit existant il est ignoré
     * sans erreur : un stock se corrige par un ajustement, que le serveur rejoue
     * depuis l'état réel — jamais par un écrasement venu d'un poste.
     *
     * ⚠️ Un renvoi du même `id` est un succès (modification) : le poste peut
     * renvoyer ce dont il n'a pas reçu l'accusé sans créer de doublon.
     *
     * Ticket S-T5 — un produit CRÉÉ au poste que le serveur connaît déjà (même nom, catégorie, unité et filière,
     * `FusionReferentielsService`) n'est pas créé une seconde fois : acquitté ET rendu dans `merged`.
     */
    private function pushProducts(array $produits, $utilisateur, ?string $poste = null): array
    {
        $accepted = [];
        $rejected = [];
        $merged = [];
        $service = app(ProductCatalogService::class);
        $fusion = app(FusionReferentielsService::class);

        foreach ($produits as $data) {
            $id = $data['id'] ?? null;

            if (! $utilisateur || ! $utilisateur->can('manage-stocks')) {
                $rejected[] = ['id' => $id, 'reason' => 'Votre rôle ne permet pas de créer ou modifier un produit.'];

                continue;
            }

            try {
                if (! is_string($id) || ! Str::isUuid($id)) {
                    throw ValidationException::withMessages(['id' => 'Identifiant de produit invalide.']);
                }

                // Ticket S-T5 — renvoi d'un identifiant déjà fusionné : même réponse, rien d'écrit.
                if ($deja = $fusion->correspondance('products', $id)) {
                    $accepted[] = $id;
                    $merged[] = $deja;

                    continue;
                }

                $existant = Product::find($id);

                $valides = validator(
                    $data,
                    $service->regles((string) ($data['pricing_mode'] ?? ''), $existant === null),
                    $service->messages() + MotifsRefusPush::messages(),
                    MotifsRefusPush::attributs(),
                )->validate();

                // Ticket S-T5 — création d'un produit que le serveur connaît déjà (même clé naturelle) : fusion.
                if ($existant === null && ($fusionne = $fusion->fusionnerCreation('products', $id, $valides, $poste, $utilisateur->id))) {
                    $accepted[] = $id;
                    $merged[] = $fusionne;

                    continue;
                }

                $existant === null
                    ? $service->creer($valides, $id)
                    : $service->modifier($existant, $valides, false);

                $accepted[] = $id;
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected, 'merged' => $merged];
    }

    /**
     * Fiches fournisseurs créées, modifiées ou archivées au poste (ticket 15.17).
     *
     * ⚠️⚠️ AVEC `products`, LE SEUL AUTRE RÉFÉRENTIEL OÙ LE POSTE ÉCRIT. Le serveur garde
     * la main : mêmes règles que la page web (`SupplierCatalogService`), droit
     * `manage-achats`, `id` du poste conservé. Un renvoi du même `id` est une
     * modification, jamais un doublon. Archiver = `is_active: false`.
     *
     * Ticket S-T5 — une fiche CRÉÉE au poste que le serveur connaît déjà (même nom, même téléphone,
     * `FusionReferentielsService`) n'est pas créée une seconde fois : acquittée ET rendue dans `merged`.
     */
    private function pushSuppliers(array $fournisseurs, $utilisateur, ?string $poste = null): array
    {
        $accepted = [];
        $rejected = [];
        $merged = [];
        $service = app(\App\Services\SupplierCatalogService::class);
        $fusion = app(FusionReferentielsService::class);

        foreach ($fournisseurs as $data) {
            $id = $data['id'] ?? null;

            if (! $utilisateur || ! $utilisateur->can('manage-achats')) {
                $rejected[] = ['id' => $id, 'reason' => 'Votre rôle ne permet pas de créer ou modifier un fournisseur.'];

                continue;
            }

            try {
                if (! is_string($id) || ! Str::isUuid($id)) {
                    throw ValidationException::withMessages(['id' => 'Identifiant de fournisseur invalide.']);
                }

                // Ticket S-T5 — renvoi d'un identifiant déjà fusionné (accusé perdu, ou poste ancien qui modifie ou
                // archive SA copie) : même réponse, RIEN d'écrit sur la fiche partagée.
                if ($deja = $fusion->correspondance('suppliers', $id)) {
                    $accepted[] = $id;
                    $merged[] = $deja;

                    continue;
                }

                $valides = validator($data, $service->regles(), MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();
                $existant = \App\Models\Supplier::find($id);

                // Ticket S-T5 — création d'une fiche que le serveur connaît déjà (même clé naturelle) : fusion.
                if ($existant === null && ($fusionne = $fusion->fusionnerCreation('suppliers', $id, $valides, $poste, $utilisateur->id))) {
                    $accepted[] = $id;
                    $merged[] = $fusionne;

                    continue;
                }

                $existant === null
                    ? $service->creer($valides, $id)
                    : $service->modifier($existant, $valides);

                $accepted[] = $id;
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected, 'merged' => $merged];
    }

    /**
     * Fiches clients créées, modifiées ou archivées au poste (ticket 15.18).
     *
     * Mêmes règles que la page « Liste des Clients » (`CustomerCatalogService`), droit
     * `manage-ventes`, `id` du poste conservé. Un renvoi du même `id` est une modification,
     * jamais un doublon. Archiver = `is_active: false`. Le plafond de crédit ne se lit pas
     * dans l'envoi : un poste ne relève pas le plafond d'un client.
     *
     * Ticket S-T5 — une fiche CRÉÉE au poste que le serveur connaît déjà (même nom, même téléphone ; jamais sans
     * téléphone, `FusionReferentielsService`) n'est pas créée une seconde fois : acquittée ET rendue dans `merged`.
     */
    private function pushCustomers(array $clients, $utilisateur, ?string $poste = null): array
    {
        $accepted = [];
        $rejected = [];
        $merged = [];
        $service = app(\App\Services\CustomerCatalogService::class);
        $fusion = app(FusionReferentielsService::class);

        foreach ($clients as $data) {
            $id = $data['id'] ?? null;

            if (! $utilisateur || ! $utilisateur->can('manage-ventes')) {
                $rejected[] = ['id' => $id, 'reason' => 'Votre rôle ne permet pas de créer ou modifier un client.'];

                continue;
            }

            try {
                if (! is_string($id) || ! Str::isUuid($id)) {
                    throw ValidationException::withMessages(['id' => 'Identifiant de client invalide.']);
                }

                // Ticket S-T5 — renvoi d'un identifiant déjà fusionné (accusé perdu, ou poste ancien qui modifie ou
                // archive SA copie) : même réponse, RIEN d'écrit sur la fiche partagée.
                if ($deja = $fusion->correspondance('customers', $id)) {
                    $accepted[] = $id;
                    $merged[] = $deja;

                    continue;
                }

                $valides = validator($data, $service->regles(), MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();
                $existant = \App\Models\Customer::find($id);

                // Ticket S-T5 — création d'une fiche que le serveur connaît déjà (même clé naturelle) : fusion.
                if ($existant === null && ($fusionne = $fusion->fusionnerCreation('customers', $id, $valides, $poste, $utilisateur->id))) {
                    $accepted[] = $id;
                    $merged[] = $fusionne;

                    continue;
                }

                $existant === null
                    ? $service->creer($valides, $id)
                    : $service->modifier($existant, $valides);

                $accepted[] = $id;
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected, 'merged' => $merged];
    }

    /**
     * Courriers enregistrés, modifiés ou archivés au poste (ticket 15.23).
     *
     * Mêmes règles que la page « Gestion des Courriers » (`CourrierService`), droit
     * `manage-administration`, `id` du poste conservé. Un renvoi du même `id` est une
     * modification, jamais un doublon. La RÉFÉRENCE est attribuée par le serveur et ne change
     * jamais ; celle qu'un poste enverrait est ignorée. Archiver = `is_active: false`
     * (idempotent ; un `id` inconnu est refusé avec motif : on n'archive pas ce qu'on ne connaît pas).
     */
    private function pushMails(array $courriers, $utilisateur): array
    {
        $accepted = [];
        $rejected = [];
        $service = app(\App\Services\CourrierService::class);

        foreach ($courriers as $data) {
            $data = is_array($data) ? $data : [];
            $id = $data['id'] ?? null;

            if (! $utilisateur || ! $utilisateur->can('manage-administration')) {
                $rejected[] = ['id' => $id, 'reason' => 'Votre rôle ne permet pas de créer ou modifier un courrier.'];

                continue;
            }

            try {
                if (! is_string($id) || ! Str::isUuid($id)) {
                    throw ValidationException::withMessages(['id' => 'Identifiant de courrier invalide.']);
                }

                $existant = \App\Models\Correspondence::find($id);
                $veutArchiver = $this->veutRetirer($data);

                if ($veutArchiver) {
                    if ($existant === null) {
                        throw ValidationException::withMessages(['id' => 'Courrier inconnu : impossible de l\'archiver.']);
                    }
                    $service->archiver($existant);
                    $accepted[] = $id;

                    continue;
                }

                $valides = validator($data, $service->regles(), MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                if ($existant === null) {
                    $service->creer($valides, $id);
                } elseif (! $existant->is_active) {
                    throw ValidationException::withMessages(['id' => 'Ce courrier est archivé : il ne peut plus être modifié.']);
                } else {
                    $service->modifier($existant, $valides);
                }

                $accepted[] = $id;
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Documents archivés (coffre-fort) enregistrés, modifiés ou retirés au poste (ticket 15.24).
     *
     * Mêmes règles que la page « Archivage des Documents » (`ArchiveDocumentService`), droit
     * `manage-administration`, `id` du poste conservé. Un renvoi du même `id` est une
     * modification, jamais un doublon. Retirer = `is_active: false` (idempotent ; un `id` inconnu
     * est refusé avec motif : on ne retire pas ce qu'on ne connaît pas). Un document déjà retiré
     * ne se modifie plus.
     */
    private function pushArchivedDocuments(array $documents, $utilisateur): array
    {
        $accepted = [];
        $rejected = [];
        $service = app(\App\Services\ArchiveDocumentService::class);

        foreach ($documents as $data) {
            $data = is_array($data) ? $data : [];
            $id = $data['id'] ?? null;

            if (! $utilisateur || ! $utilisateur->can('manage-administration')) {
                $rejected[] = ['id' => $id, 'reason' => 'Votre rôle ne permet pas d\'archiver ou modifier un document.'];

                continue;
            }

            try {
                if (! is_string($id) || ! Str::isUuid($id)) {
                    throw ValidationException::withMessages(['id' => 'Identifiant de document invalide.']);
                }

                $existant = \App\Models\ArchivedDocument::find($id);
                $veutRetirer = $this->veutRetirer($data);

                if ($veutRetirer) {
                    if ($existant === null) {
                        throw ValidationException::withMessages(['id' => 'Document inconnu : impossible de le retirer.']);
                    }
                    $service->archiver($existant);
                    $accepted[] = $id;

                    continue;
                }

                $valides = validator($data, $service->regles(), MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                if ($existant === null) {
                    $service->creer($valides, $id);
                } elseif (! $existant->is_active) {
                    throw ValidationException::withMessages(['id' => 'Ce document est retiré des archives : il ne peut plus être modifié.']);
                } else {
                    $service->modifier($existant, $valides);
                }

                $accepted[] = $id;
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Documents administratifs (registre : attestations, certificats, notes, correspondances)
     * enregistrés, modifiés ou retirés au poste (ticket 15.25).
     *
     * Mêmes règles que la page « Documents Administratifs » (`DocumentAdministratifService`),
     * droit `manage-administration`, `id` du poste conservé. Un renvoi du même `id` est une
     * modification, jamais un doublon. Retirer = `is_active: false` (idempotent ; un `id` inconnu
     * est refusé avec motif). Un document retiré ne se modifie plus.
     *
     * `status` absent (ou null) : `en_attente` à la création ; à la modification, le statut
     * existant est CONSERVÉ (un envoi sans statut ne rétrograde pas un document signé).
     * Aucun fichier n'est généré ni reçu : c'est un registre.
     */
    private function pushAdministrativeDocuments(array $documents, $utilisateur): array
    {
        $accepted = [];
        $rejected = [];
        $service = app(\App\Services\DocumentAdministratifService::class);

        foreach ($documents as $data) {
            $data = is_array($data) ? $data : [];
            $id = $data['id'] ?? null;

            if (! $utilisateur || ! $utilisateur->can('manage-administration')) {
                $rejected[] = ['id' => $id, 'reason' => 'Votre rôle ne permet pas d\'enregistrer ou modifier un document administratif.'];

                continue;
            }

            try {
                if (! is_string($id) || ! Str::isUuid($id)) {
                    throw ValidationException::withMessages(['id' => 'Identifiant de document invalide.']);
                }

                $existant = AdministrativeDocument::find($id);
                $veutRetirer = $this->veutRetirer($data);

                if ($veutRetirer) {
                    if ($existant === null) {
                        throw ValidationException::withMessages(['id' => 'Document inconnu : impossible de le retirer.']);
                    }
                    $service->archiver($existant);
                    $accepted[] = $id;

                    continue;
                }

                if (($data['status'] ?? null) === null) {
                    $data['status'] = $existant?->status ?? \App\Services\DocumentAdministratifService::STATUT_PAR_DEFAUT;
                }

                $valides = validator($data, $service->regles(), MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                if ($existant === null) {
                    $service->creer($valides, $id);
                } elseif (! $existant->is_active) {
                    throw ValidationException::withMessages(['id' => 'Ce document est retiré du registre : il ne peut plus être modifié.']);
                } else {
                    $service->modifier($existant, $valides);
                }

                $accepted[] = $id;
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Le poste demande-t-il le RETRAIT (archivage logique) de l'enregistrement ? (ticket 15.25)
     *
     * Commun à `mails`, `archived_documents` et `administrative_documents`. Avant 15.25 le serveur
     * ne reconnaissait un retrait que pour `is_active === false` STRICT : un `0` ou un `"0"`
     * (booléen sérialisé en entier, ce que fait une base SQLite) passait pour une MODIFICATION et,
     * si les champs étaient complets, était acceptée en silence — l'enregistrement restait actif
     * alors que le poste le croyait retiré.
     *
     * - absent ou `null`      : pas de retrait (champ facultatif) ;
     * - `false`, `0`, `"0"`   : retrait ;
     * - `true`, `1`, `"1"`    : pas de retrait ;
     * - toute autre valeur    : REFUSÉE avec motif (jamais devinée, jamais un 500).
     *
     * @throws ValidationException
     */
    private function veutRetirer(array $data): bool
    {
        if (! array_key_exists('is_active', $data) || $data['is_active'] === null) {
            return false;
        }

        $v = $data['is_active'];

        if (in_array($v, [false, 0, '0'], true)) {
            return true;
        }

        if (in_array($v, [true, 1, '1'], true)) {
            return false;
        }

        throw ValidationException::withMessages(['is_active' => 'Valeur de is_active invalide : un booléen est attendu (true ou false).']);
    }

    /**
     * Avances clients encaissées au poste (ticket 15.19).
     *
     * ⚠️⚠️ LE POSTE N'ÉCRIT QUE LE FAIT : « tant, de ce client, dans ce compte, ce jour ». L'entrée en
     * trésorerie (solde du compte ET classe 5) et l'écriture Débit 5xx / Crédit 419 sont faites ICI,
     * par `CustomerAdvanceService`, partagé avec la page web — dans une seule transaction.
     *
     * ⚠️ IDEMPOTENCE : un `id` déjà reçu est acquitté sans rien rejouer (sinon l'argent entrerait
     * deux fois en caisse). Un refus (droit, client ou compte inconnus, exercice clos, plan
     * comptable incomplet) est rendu AVEC SON MOTIF et n'échoue que cette avance.
     */
    private function pushCustomerAdvances(array $avances, $utilisateur, ?string $deviceId): array
    {
        $accepted = [];
        $rejected = [];
        $service = app(\App\Services\CustomerAdvanceService::class);

        foreach ($avances as $data) {
            $id = is_array($data) ? ($data['id'] ?? null) : null;

            if (! $utilisateur || ! $utilisateur->can('manage-ventes')) {
                $rejected[] = ['id' => $id, 'reason' => "Votre rôle ne permet pas d'enregistrer une avance client."];

                continue;
            }

            try {
                $valides = validator(is_array($data) ? $data : [], [
                    'id' => ['required', 'uuid'],
                    'customer_id' => ['required', 'uuid'],
                    'treasury_account_id' => ['required', 'uuid'],
                    'amount' => ['required', 'numeric', 'min:1'],
                    'advance_date' => ['required', 'date'],
                    'payment_mode' => ['nullable', 'string', 'max:20'],
                    'motif' => ['nullable', 'string', 'max:255'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                $service->recevoir(
                    $valides['customer_id'],
                    (float) $valides['amount'],
                    $valides['treasury_account_id'],
                    $valides['advance_date'],
                    $valides['payment_mode'] ?? null,
                    $valides['motif'] ?? null,
                    $valides['id'],
                    $deviceId,
                );

                $accepted[] = $valides['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
                $rejected[] = ['id' => $id, 'reason' => $e->getMessage()];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Imputations d'avances saisies au poste (ticket 15.19).
     *
     * ⚠️⚠️ LE POSTE N'IMPUTE RIEN : il envoie « tant de cette avance sur cette créance ». Le plafond
     * (min du montant, du reste de l'avance et du solde de la créance), `amount_paid`/`amount_used` et
     * l'écriture Débit 419 / Crédit 411 sont refaits ICI par `CustomerAdvanceService`. Une
     * créance se désigne par `receivable_id` OU par `sale_id` : une vente à crédit du même envoi
     * vient d'être créée côté serveur, le poste ne peut pas connaître l'identifiant de sa créance.
     *
     * ⚠️ IDEMPOTENCE : un `id` déjà reçu est acquitté sans rien rejouer.
     */
    private function pushAdvanceImputations(array $imputations, $utilisateur, ?string $deviceId): array
    {
        $accepted = [];
        $rejected = [];
        $service = app(\App\Services\CustomerAdvanceService::class);

        foreach ($imputations as $data) {
            $id = is_array($data) ? ($data['id'] ?? null) : null;

            if (! $utilisateur || ! $utilisateur->can('manage-ventes')) {
                $rejected[] = ['id' => $id, 'reason' => "Votre rôle ne permet pas d'imputer une avance client."];

                continue;
            }

            try {
                $valides = validator(is_array($data) ? $data : [], [
                    'id' => ['required', 'uuid'],
                    'customer_advance_id' => ['required', 'uuid'],
                    'receivable_id' => ['required_without:sale_id', 'nullable', 'uuid'],
                    'sale_id' => ['required_without:receivable_id', 'nullable', 'uuid'],
                    'amount' => ['required', 'numeric', 'min:1'],
                    'imputation_date' => ['required', 'date'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                $receivableId = $valides['receivable_id'] ?? null;

                if ($receivableId === null) {
                    $receivableId = \App\Models\Receivable::where('sale_id', $valides['sale_id'])->value('id');

                    if ($receivableId === null && \App\Models\AdvanceImputation::find($valides['id']) === null) {
                        throw ValidationException::withMessages(['sale_id' => 'Aucune créance pour cette vente.']);
                    }
                }

                $service->imputer(
                    $valides['customer_advance_id'],
                    (string) $receivableId,
                    (float) $valides['amount'],
                    $valides['imputation_date'],
                    $valides['id'],
                    $deviceId,
                );

                $accepted[] = $valides['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
                $rejected[] = ['id' => $id, 'reason' => $e->getMessage()];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Règlements fournisseurs saisis au poste (ticket 15.16).
     *
     * ⚠️⚠️ LE POSTE N'IMPUTE RIEN : il envoie « tant à ce fournisseur, depuis ce compte ».
     * L'imputation sur les dettes les plus anciennes, la sortie de trésorerie ET
     * l'écriture 401/5xx sont refaites ICI, par le service partagé avec la page web —
     * jamais appliquées telles quelles depuis un poste (même règle que les ajustements
     * de stock : un delta aveugle hors ligne décrémenterait deux fois).
     *
     * ⚠️ IDEMPOTENCE : un `id` déjà reçu est acquitté sans rien rejouer. Sans cela, un
     * accusé perdu en route ferait décaisser deux fois la trésorerie.
     *
     * ⚠️ Un refus (droit, dette absente, exercice clos) est rendu AVEC SON MOTIF et
     * n'échoue que ce règlement : l'annulation de la transaction garantit qu'aucune
     * caisse fausse ne subsiste.
     */
    private function pushSupplierPayments(array $paiements, $utilisateur, ?string $deviceId): array
    {
        $accepted = [];
        $rejected = [];
        $service = app(\App\Services\SupplierSettlementService::class);

        foreach ($paiements as $data) {
            $id = $data['id'] ?? null;

            if (! $utilisateur || ! $utilisateur->can('manage-achats')) {
                $rejected[] = ['id' => $id, 'reason' => 'Votre rôle ne permet pas de régler un fournisseur.'];

                continue;
            }

            try {
                $valides = validator($data, [
                    'id' => ['required', 'uuid'],
                    'supplier_id' => ['required', 'uuid', 'exists:suppliers,id'],
                    'treasury_account_id' => ['required', 'uuid', 'exists:treasury_accounts,id'],
                    'amount' => ['required', 'numeric', 'min:1'],
                    'payment_date' => ['required', 'date'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                if (\App\Models\SupplierPayment::find($valides['id']) !== null) {
                    $accepted[] = $valides['id'];

                    continue;
                }

                $service->regler(
                    $valides['supplier_id'],
                    (float) $valides['amount'],
                    $valides['treasury_account_id'],
                    $valides['payment_date'],
                    $valides['id'],
                    $deviceId,
                );

                $accepted[] = $valides['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
                $rejected[] = ['id' => $id, 'reason' => $e->getMessage()];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Identifiants (UUID du retour ET id de l'achat) des retours fournisseur du paquet - pour le garde-fou de
     * `pushStockAdjustments`.
     *
     * @return array<int, string>
     */
    private function identifiantsDeRetours($retours): array
    {
        return collect(is_array($retours) ? $retours : [])
            ->filter(fn ($r) => is_array($r))
            ->flatMap(fn ($r) => [$r['id'] ?? null, $r['purchase_id'] ?? null])
            ->filter(fn ($v) => is_string($v) && $v !== '')
            ->unique()
            ->values()
            ->all();
    }

    /**
     * Retours fournisseur saisis au poste (ticket 15.20).
     *
     * ⚠️⚠️ LE POSTE N'ENVOIE QUE LE FAIT : « cet achat est retourné, pour ce motif, tel jour ». La décrémentation du
     * stock (jamais négatif), la contre-passation de l'écriture d'achat, l'annulation de la part non payée de la dette
     * et la créance 409 sur la part payée sont faites ICI, par `PurchaseReturnService`, partagé avec la page web, en
     * une transaction. Le retour est l'ANNULATION COMPLÈTE de l'achat (D6).
     *
     * ⚠️ IDEMPOTENCE : `id` = UUID du retour (`return_batch_id`) ; un `id` déjà reçu est acquitté sans rien rejouer.
     * Un second retour du même achat sous un AUTRE id est refusé avec motif.
     */
    private function pushPurchaseReturns(array $retours, $utilisateur, ?string $deviceId): array
    {
        $accepted = [];
        $rejected = [];
        $service = app(\App\Services\PurchaseReturnService::class);

        foreach ($retours as $data) {
            $id = is_array($data) ? ($data['id'] ?? null) : null;

            if (! $utilisateur || ! $utilisateur->can('manage-achats')) {
                $rejected[] = ['id' => $id, 'reason' => "Votre rôle ne permet pas d'enregistrer un retour fournisseur."];

                continue;
            }

            try {
                $valides = validator(is_array($data) ? $data : [], [
                    'id' => ['required', 'uuid'],
                    'purchase_id' => ['required', 'uuid'],
                    'reason' => ['required', 'string', 'max:500'],
                    'return_date' => ['required', 'date'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                $service->annuler(
                    $valides['purchase_id'],
                    $valides['reason'],
                    $valides['return_date'],
                    $valides['id'],
                    $deviceId,
                );

                $accepted[] = $valides['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
                // Un refus comptable rejette CE retour, jamais l'envoi entier : la transaction annulée ne laisse
                // ni stock, ni dette, ni écriture.
                $rejected[] = ['id' => $id, 'reason' => $e->getMessage()];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * 🔴→✅ TICKET AV1 — RETOURS ET AVOIRS CLIENTS SAISIS AU POSTE (écran « Retours et Avoirs »).
     *
     * ⚠️⚠️ LE POSTE N'ENVOIE QUE LA DEMANDE : « ce produit, de cette vente, en telle quantité, pour tel motif, tel jour,
     * à réintégrer ou à réformer, pour tel montant ». La numérotation `AV-AAAA-NNN`, le stock (réintégré), l'écriture
     * inverse 701 / 443 / 411 et le journal d'audit sont faits ICI par `AvoirClientService`, le point de passage de
     * `RetoursAvoirs::saveReturn()` — jamais une seconde implémentation.
     *
     * ABSORBEUR STRICT (refus MOTIVÉ de CET avoir seul ; la transaction annulée ne laisse ni stock ni écriture) :
     * vente inconnue ou annulée, produit absent de la vente, quantité au-delà de « vendu − déjà retourné », montant
     * au-delà de « ligne − déjà crédité », date future ou antérieure à la vente, exercice absent ou clos, plan
     * comptable incomplet, droit `manage-ventes`.
     *
     * ⚠️ IDEMPOTENCE : `id` = UUID de l'avoir né sur le poste ; un `id` déjà reçu est acquitté sans rien rejouer. Un
     * avoir connu renvoyé au statut `traite` est marqué traité (« Marquer comme traité » du web), une seule fois.
     */
    private function pushCreditNotes(array $avoirs, $utilisateur): array
    {
        $accepted = [];
        $rejected = [];
        $service = app(AvoirClientService::class);

        foreach ($avoirs as $data) {
            $id = is_array($data) ? ($data['id'] ?? null) : null;

            if (! $utilisateur || ! $utilisateur->can('manage-ventes')) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::roleInsuffisant('credit_notes')];

                continue;
            }

            try {
                $valides = validator(is_array($data) ? $data : [], [
                    'id' => ['required', 'uuid'],
                    'sale_id' => ['required', 'uuid'],
                    'product_id' => ['required', 'uuid', 'exists:products,id'],
                    'qty' => ['required', 'numeric', 'gt:0'],
                    'amount' => ['required', 'numeric', 'min:0'],
                    'reason' => ['required', 'string', 'max:255'],
                    'decision' => ['required', 'in:reintegre,reforme'],
                    'inspection_notes' => ['nullable', 'string', 'max:2000'],
                    'status' => ['nullable', 'in:en_attente,traite'],
                    'credit_date' => ['required', 'date'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                $existant = \App\Models\CreditNote::find($valides['id']);

                if ($existant === null) {
                    $existant = $service->enregistrer($valides, $valides['id'], Carbon::parse($valides['credit_date']));
                }

                if (($valides['status'] ?? null) === 'traite') {
                    $service->marquerTraite($existant);
                }

                $accepted[] = $valides['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException|\App\Exceptions\AvoirClientRefuseException $e) {
                $rejected[] = ['id' => $id, 'reason' => 'Retour refusé : '.$e->getMessage()];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * 🔴→✅ TICKET ARC2 — DEMANDES DE LA CORBEILLE SAISIES AU POSTE (« Restaurer », « Supprimer définitivement »).
     *
     * ⚠️⚠️ LE POSTE N'ENVOIE QUE LA DEMANDE : « restaurer / supprimer cet élément de ce type » (et, pour une suppression,
     * le mot saisi). Les effets — `is_active`, la règle de la dépense contre-passée, l'exercice clos, le code déjà pris, la
     * vérification des références, l'effacement, l'audit — sont faits ICI par `CorbeilleService`, le point de passage de
     * la page web : jamais une seconde implémentation, jamais un `is_active` ou un DELETE venu du poste.
     *
     * ⚠️ IDEMPOTENCE : `id` = UUID de la demande née sur le poste. Une demande DÉJÀ ACCEPTÉE (acquittement perdu,
     * renvoi) est acquittée sans rien rejouer — sans cela, une restauration renvoyée serait refusée « déjà restauré » et
     * le poste croirait avoir échoué. Une demande REFUSÉE est rejugée à chaque envoi (la cause a pu disparaître : « Relancer »).
     */
    private function pushCorbeilleDemandes(array $demandes, $utilisateur, ?string $poste): array
    {
        $accepted = [];
        $rejected = [];
        $service = app(\App\Services\CorbeilleService::class);

        foreach ($demandes as $data) {
            $id = is_array($data) ? ($data['id'] ?? null) : null;

            if (! $utilisateur || ! $utilisateur->can('manage-parametres')) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::roleInsuffisant('corbeille_demandes')];

                continue;
            }

            try {
                $valides = validator(is_array($data) ? $data : [], [
                    'id' => ['required', 'uuid'],
                    'type' => ['required', 'string', 'max:40'],
                    'element_id' => ['required', 'uuid'],
                    'action' => ['required', 'in:restaurer,supprimer'],
                    'confirmation' => ['nullable', 'string', 'max:50'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];

                continue;
            }

            if (\App\Models\CorbeilleOperation::query()->whereKey($valides['id'])->where('issue', 'accepte')->exists()) {
                $accepted[] = $valides['id'];

                continue;
            }

            $resultat = $valides['action'] === 'restaurer'
                ? $service->tenterRestauration($valides['type'], $valides['element_id'], $poste, $utilisateur, $valides['id'])
                : $service->supprimerDefinitivement($valides['type'], $valides['element_id'], (string) ($valides['confirmation'] ?? ''), $poste, $utilisateur, $valides['id']);

            if ($resultat['ok']) {
                $accepted[] = $valides['id'];

                continue;
            }

            // Un refus laisse sa trace (qui, quoi, depuis quel poste, pourquoi) sous un identifiant PROPRE : l'identifiant de
            // la demande reste libre pour la relance.
            $service->journaliser($valides['action'], $valides['type'], $valides['element_id'], null, 'refuse', $resultat['message'], $utilisateur, $poste);
            $rejected[] = ['id' => $valides['id'], 'reason' => $resultat['message']];
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Remboursements fournisseurs saisis au poste (ticket 15.20, D8).
     *
     * ⚠️⚠️ LE POSTE N'ENVOIE QUE LE FAIT : « tant reçu de ce fournisseur, sur ce compte ». Le plafond (créance
     * fournisseur ouverte), l'entrée en trésorerie (solde du compte ET classe 5) et l'écriture Débit trésorerie /
     * Crédit 409 sont faits ICI par `SupplierRefundService`, partagé avec la page web, dans une seule transaction.
     *
     * ⚠️ IDEMPOTENCE : un `id` déjà reçu est acquitté sans second encaissement. Refus avec motif (droit, aucune
     * créance ouverte, exercice clos, plan comptable incomplet) ; seul ce remboursement échoue.
     */
    private function pushSupplierRefunds(array $remboursements, $utilisateur, ?string $deviceId): array
    {
        $accepted = [];
        $rejected = [];
        $service = app(\App\Services\SupplierRefundService::class);

        foreach ($remboursements as $data) {
            $id = is_array($data) ? ($data['id'] ?? null) : null;

            if (! $utilisateur || ! $utilisateur->can('manage-achats')) {
                $rejected[] = ['id' => $id, 'reason' => "Votre rôle ne permet pas d'enregistrer un remboursement fournisseur."];

                continue;
            }

            try {
                $valides = validator(is_array($data) ? $data : [], [
                    'id' => ['required', 'uuid'],
                    'supplier_id' => ['required', 'uuid'],
                    'treasury_account_id' => ['required', 'uuid'],
                    'amount' => ['required', 'numeric', 'min:1'],
                    'refund_date' => ['required', 'date'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                $service->rembourser(
                    $valides['supplier_id'],
                    (float) $valides['amount'],
                    $valides['treasury_account_id'],
                    $valides['refund_date'],
                    $valides['id'],
                    $deviceId,
                );

                $accepted[] = $valides['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
                $rejected[] = ['id' => $id, 'reason' => $e->getMessage()];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    private function pushAttendance(array $records): array
    {
        $accepted = [];
        $rejected = [];

        foreach ($records as $data) {
            try {
                $validated = validator($data, [
                    'id' => ['required', 'uuid'],
                    'employee_id' => ['required', 'uuid', 'exists:employees,id'],
                    'attendance_date' => ['required', 'date', 'before_or_equal:today'],
                    'check_in' => ['nullable', 'date_format:H:i,H:i:s'],
                    'check_out' => ['nullable', 'date_format:H:i,H:i:s'],
                    'status' => ['required', 'in:present,absent,conge,maladie,retard'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                $existant = AttendanceRecord::where('employee_id', $validated['employee_id'])
                    ->whereDate('attendance_date', $validated['attendance_date'])
                    ->first();

                $charge = [
                    'check_in' => $validated['check_in'] ?? null,
                    'check_out' => $validated['check_out'] ?? null,
                    'status' => $validated['status'],
                    'is_active' => true,
                ];

                if ($existant) {
                    $existant->update($charge);
                } else {
                    $pointage = new AttendanceRecord();
                    // ⚠️ MEME PIEGE QUE LES ACHATS (14.78) : `id` n'est pas
                    // remplissable, `create(['id' => …])` l'ignorerait EN
                    // SILENCE et le serveur forgerait son propre UUID.
                    $pointage->id = $validated['id'];
                    $pointage->fill(array_merge($charge, [
                        'employee_id' => $validated['employee_id'],
                        'attendance_date' => $validated['attendance_date'],
                    ]));
                    $pointage->save();
                }

                $accepted[] = $validated['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $data['id'] ?? null, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Ticket DEV — devis créés, modifiés, avancés dans leur cycle ou archivés au poste (droit `manage-ventes`).
     *
     * Jouée par `SaisieDevisAction`, le point de passage de l'écran web « Devis & Proforma » : mêmes règles, mêmes
     * messages, même audit. Le poste envoie le FAIT (le devis tel qu'il est) :
     *  - le numéro `DEV-AAAA-NNN` n'est JAMAIS lu : le serveur l'attribue à la création et le rend au tirage ;
     *  - le statut avance pas à pas (`brouillon → envoyé → accepté | refusé`) ; un retour en arrière, ou `facture`, est
     *    refusé avec son motif (`facture` n'est jamais atteint par un geste du poste : il ne facture rien ; il ne revient que sur un devis déjà facturé que le poste archive) ;
     *  - un exercice clos qui couvre la date du devis le refuse, à la création comme à la modification ou à l'archivage ;
     *  - idempotent : un renvoi identique n'écrit rien ; `is_active: false` archive (un second archivage ne fait rien) ;
     *    un devis archivé ou facturé ne se modifie plus.
     * Chaque devis est jugé seul, dans sa transaction : un refus ne fait échouer ni l'envoi ni les autres devis.
     *
     * @return array{accepted: array<int, string>, rejected: array<int, array{id: mixed, reason: string}>}
     */
    private function pushQuotes(array $devis): array
    {
        $accepted = [];
        $rejected = [];
        $saisie = app(\App\Actions\SaisieDevisAction::class);

        foreach ($devis as $data) {
            $data = is_array($data) ? $data : [];

            try {
                $valides = validator($data, [
                    'id' => ['required', 'uuid'],
                    'customer_id' => ['required', 'uuid', 'exists:customers,id'],
                    'articles_description' => ['required', 'string', 'max:2000'],
                    'amount' => ['required', 'numeric', 'min:0'],
                    'tva_rate' => ['required', 'numeric', 'min:0', 'max:100'],
                    'validity_days' => ['required', 'integer', 'min:1'],
                    'quote_date' => ['required', 'date'],
                    'note' => ['nullable', 'string'],
                    'status' => ['sometimes', 'in:brouillon,envoye,accepte,refuse,facture'],
                    'is_active' => ['sometimes', 'boolean'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                $statut = $valides['status'] ?? 'brouillon';
                $archive = array_key_exists('is_active', $valides) && ! filter_var($valides['is_active'], FILTER_VALIDATE_BOOLEAN);
                $existant = Quote::find($valides['id']);

                // Une seule transaction par devis : une création suivie d'un refus (statut, exercice) n'écrit rien.
                DB::transaction(function () use ($saisie, $valides, $statut, $archive, $existant) {
                    if ($existant === null) {
                        $saisie->creer($valides, $valides['id']);
                        $saisie->aligner($valides['id'], $statut);
                        if ($archive) {
                            $saisie->archiver($valides['id']);
                        }

                        return;
                    }

                    if ($archive) {
                        // Archivage : acquitté tel quel si le devis l'est déjà (renvoi), sinon archivé.
                        $saisie->archiver($existant->id);

                        return;
                    }

                    // Ticket DEV3 — un devis CONVERTI (`facture`) renvoyé tel que le poste l'a vu avant la conversion (`accepte`,
                    // mêmes champs : la réponse d'un envoi précédent s'est perdue) est acquitté, jamais refusé comme modification
                    // d'un devis facturé.
                    $memeStatut = $existant->status === $statut || ($existant->status === 'facture' && $statut === 'accepte');
                    if ($saisie->identique($existant, $valides) && $memeStatut && $existant->is_active) {
                        return;
                    }

                    $saisie->modifier($existant->id, $valides);
                    $saisie->aligner($existant->id, $statut);
                });

                $accepted[] = $valides['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $data['id'] ?? null, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Ticket DEV3 — DEMANDES DE CONVERSION « devis accepté → facture » du poste (`quote_conversions`).
     *
     * ⚠️ LE POSTE N'ENVOIE QUE LA DEMANDE : `{ id: <uuid du devis>, requested_at?: <instant du clic, ISO 8601> }`. Le
     * serveur crée la facture (vente à crédit sans ligne), la créance et l'écriture, la numérote (`FV-AAAA-XXXXXX`) et
     * rend le lien dans `invoices[<uuid du devis>] = { sale_id, invoice_number }` : tout passe par
     * `ConvertirDevisEnFactureAction`, le point de passage de l'écran web « Convertir en Facture ».
     *
     * ⚠️ IDEMPOTENCE PAR L'UUID DU DEVIS : un devis déjà converti est acquitté avec SA facture, sans seconde pièce (la
     * réponse d'un envoi précédent s'est perdue). Refus, un par un, avec leur motif lisible (statut non convertible,
     * devis archivé ou inconnu, client absent ou archivé, exercice clos, date de facture future ou clôturée, plan
     * comptable incomplet, droits `manage-ventes` ET `manage-facturation`) : seule cette demande échoue.
     *
     * La facture normalisée MeCeF suit le circuit des ventes reçues (`ventesAFacturer`, après la transaction de
     * l'envoi) : aucune transmission nouvelle, rien d'ajouté côté DGI (D-MECEF-1 laissé de côté).
     *
     * @return array{accepted: array<int, string>, rejected: array<int, array{id: mixed, reason: string}>, invoices: array<string, array{sale_id: string, invoice_number: string}>}
     */
    private function pushQuoteConversions(array $demandes, $utilisateur): array
    {
        $accepted = [];
        $rejected = [];
        $invoices = [];

        foreach ($demandes as $data) {
            $data = is_array($data) ? $data : [];
            $id = $data['id'] ?? null;

            if (! $utilisateur || ! $utilisateur->can('manage-ventes') || ! $utilisateur->can('manage-facturation')) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::roleInsuffisant('quote_conversions')];

                continue;
            }

            try {
                $valides = validator($data, [
                    'id' => ['required', 'uuid'],
                    'requested_at' => ['nullable', 'date'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                $resultat = app(\App\Actions\ConvertirDevisEnFactureAction::class)->execute(
                    $valides['id'],
                    ! empty($valides['requested_at']) ? Carbon::parse($valides['requested_at']) : null,
                );

                if (! $resultat['deja']) {
                    $this->ventesAFacturer[] = $resultat['vente']->id;
                }

                $accepted[] = $valides['id'];
                $invoices[$valides['id']] = [
                    'sale_id' => $resultat['vente']->id,
                    'invoice_number' => $resultat['vente']->numero_facture,
                ];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            } catch (\App\Exceptions\ConversionDevisRefuseeException $e) {
                $rejected[] = ['id' => $id, 'reason' => $e->getMessage()];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected, 'invoices' => $invoices];
    }

    /**
     * Dépenses saisies, MODIFIÉES ou ARCHIVÉES au poste.
     *
     * 🔴→✅ TICKET U14 — le poste fait ce que fait « Saisie des Dépenses » au web : créer, modifier, archiver. Les trois
     * gestes passent par `SaisieDepenseAction`, le point de passage du composant Livewire : mêmes règles (une dépense
     * comptabilisée ne change ni de montant, ni de compte de charge, ni de compte de trésorerie ; une dépense archivée
     * ne se modifie plus), mêmes effets (trésorerie, écriture, contre-passation, journal d'audit), mêmes messages — un
     * refus revient au poste avec la phrase que le web affiche sous « Montant ». Droit `manage-achats`
     * (`PERMISSION_PAR_TABLE`), celui de l'écran web. Avant U14 une dépense connue était acquittée sans rien rejouer :
     * une modification ou un archivage faits au poste étaient perdus en silence.
     *
     * Une ligne CONNUE du serveur :
     *  - `is_active: false` → archivée comme par `archiveExpense()` (contre-passation, trésorerie réintégrée) ; déjà
     *    archivée : acquittée sans rien refaire (renvoi d'un archivage dont la réponse s'est perdue) ;
     *  - identique à la dépense du serveur → acquittée sans rien rejouer (IDEMPOTENCE : renvoi d'une saisie déjà reçue) ;
     *  - différente → modifiée comme par `submitExpense()` en modification (dernier écrivain gagne, comme au web).
     * Une ligne INCONNUE est créée (décaissée, comptabilisée) ; arrivée archivée (saisie puis archivée hors ligne), elle
     * est créée PUIS archivée, comme au web : la trace des deux gestes reste au grand livre et au journal d'audit.
     *
     * 🔴→✅ TICKET DEP3 — UNE DÉPENSE, PLUSIEURS LIGNES. Le document porte ses lignes (`lines` : `id`, `label`,
     * `charge_account_id`, `amount`) dans le MÊME envoi que l'en-tête. ABSORBEUR STRICT (`SaisieDepenseAction::valider`) :
     * au moins une ligne, compte de charge existant de classe 6, montants entiers > 0, total annoncé = somme des lignes,
     * identifiants de ligne uniques, exercice clos refusé, motifs en français. Un poste non migré qui envoie encore la
     * dépense PLATE (`label`, `category`, `amount`) est accepté et converti en UNE ligne (le serveur est déployé avant
     * les postes). Une dépense comptabilisée est IMMUABLE : un renvoi identique est acquitté, toute différence refusée
     * ([SaisieDepenseAction::MESSAGE_DEJA_COMPTABILISEE]). Pièce impossible : la dépense n'est pas enregistrée.
     */
    private function pushExpenses(array $expenses): array
    {
        $accepted = [];
        $rejected = [];
        $saisie = app(\App\Actions\SaisieDepenseAction::class);

        foreach ($expenses as $data) {
            try {
                // Ticket DEP3 — ABSORBEUR STRICT : le document à lignes, ou le document PLAT d'un poste non migré (converti en
                // UNE ligne : le serveur est déployé AVANT les postes). Mêmes règles que le web, par `SaisieDepenseAction`.
                validator(is_array($data) ? $data : [], [
                    'id' => ['required', 'uuid'],
                    'is_active' => ['sometimes', 'boolean'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();
                $validated = $saisie->valider($data, $data['id'], pourLEnvoi: true);
                $validated['id'] = $data['id'];
                if (array_key_exists('is_active', $data)) {
                    $validated['is_active'] = $data['is_active'];
                }

                $archivee = array_key_exists('is_active', $validated) && ! filter_var($validated['is_active'], FILTER_VALIDATE_BOOLEAN);
                $existante = \App\Models\Expense::find($validated['id']);

                // Une seule transaction par ligne : une création suivie d'un archivage refusé (exercice) n'écrit rien.
                DB::transaction(function () use ($saisie, $validated, $existante, $archivee) {
                    if ($existante === null) {
                        $saisie->creer($validated, $validated['id']);
                        if ($archivee) {
                            $saisie->archiver($validated['id']);
                        }
                    } elseif ($archivee) {
                        $saisie->archiver($validated['id']);
                    } elseif (! $saisie->identique($existante, $validated)) {
                        $saisie->modifier($validated['id'], $validated);
                    }
                });

                $accepted[] = $validated['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $data['id'] ?? null, 'reason' => MotifsRefusPush::motif($e)];
            } catch (\App\Exceptions\DepenseNonComptabilisableException $e) {
                // Ticket DEP3 — la pièce ne peut pas être passée : la dépense n'est PAS enregistrée (motif du web).
                $rejected[] = ['id' => $data['id'] ?? null, 'reason' => $e->getMessage()];
            } catch (\App\Exceptions\DepenseNonModifiableException $e) {
                // Le refus du web, mot pour mot (dépense comptabilisée, ou archivée entre-temps au web).
                $rejected[] = ['id' => $data['id'] ?? null, 'reason' => $e->getMessage()];
            } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
                // ⚠️⚠️ UN REFUS COMPTABLE NE FAIT PAS ECHOUER TOUT L'ENVOI.
                // Aucun exercice ouvert, ou aucun qui couvre la date de la
                // depense (ou du jour, pour la contre-passation d'un archivage) :
                // l'ecriture est impossible — mais laisser remonter l'exception
                // renverrait 500 pour la requete ENTIERE : les fiches d'elevage et
                // les ventes du meme envoi seraient perdues avec elle, et le poste
                // les rejouerait sans jamais savoir pourquoi. La depense est
                // rejetee AVEC SON MOTIF, et elle seule.
                //
                // ⚠️ La transaction de la depense ayant ete annulee, le
                // decaissement n'a pas eu lieu : aucune caisse fausse ne subsiste.
                $rejected[] = ['id' => $data['id'] ?? null, 'reason' => $e->getMessage()];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Ventes POS : JAMAIS fusionnées. Chaque vente hors-ligne est une
     * transaction réelle et distincte — toujours une création, jamais une
     * mise à jour d'une vente existante par ce canal (une vente déjà
     * validée ne devrait jamais être modifiée après coup, cohérent avec
     * le reste du projet).
     */

    /**
     * @param  array<string, true>  $fichesRecues  fiches du MÊME envoi qui portent déjà ses ventes (15.30 ; S-T9 : créées par l'envoi ou réduites)
     */
    /**
     * Ticket BS1 — bandes créées, modifiées ou archivées au poste. `livestock_lots` était un référentiel en lecture
     * seule : c'est maintenant une table MIXTE (tirée ET saisie), jouée par `SaisieBandeAction` — le point de passage
     * de l'écran web « Bandes & Sujets » (mêmes règles, mêmes messages, même audit).
     *
     * ⚠️ L'EFFECTIF N'APPARTIENT PAS AU POSTE. `current_quantity` est celui des fiches (cascade du serveur) : la ligne
     * du poste n'y touche JAMAIS, sauf correction explicite de l'exploitant (`effectif_corrige`, « Modifier la Bande »
     * du web). Sans cela, une bande dont le poste change le stade écraserait l'effectif des fiches reçues d'ailleurs.
     * Le code, l'espèce, l'effectif initial et la date de création ne changent jamais après la création.
     *
     * Idempotent : un renvoi identique n'écrit rien ; une bande archivée n'est plus modifiable (le motif du web) ; un
     * second archivage est acquitté sans trace.
     *
     * @return array{accepted: array<int, string>, rejected: array<int, array{id: mixed, reason: string}>}
     */
    private function pushLots(array $bandes): array
    {
        $accepted = [];
        $rejected = [];
        $saisie = app(\App\Actions\SaisieBandeAction::class);

        foreach ($bandes as $donnees) {
            $id = is_array($donnees) ? ($donnees['id'] ?? null) : null;

            try {
                $donnees = is_array($donnees) ? $donnees : [];
                $existante = is_string($id) && \Illuminate\Support\Str::isUuid($id) ? LivestockLot::find($id) : null;
                $espece = isset($donnees['species_id']) && is_string($donnees['species_id'])
                    ? \App\Models\LivestockSpecies::find($donnees['species_id'])
                    : null;

                $valides = validator($donnees, [
                    'id' => ['required', 'uuid'],
                    // Ticket UNI : unique parmi TOUTES les bandes, casse et espaces ignorés ; le motif dit au poste quoi faire (renommer).
                    // ⚠️ Un code que la bande PORTE DÉJÀ n'est pas revérifié : un doublon antérieur à la règle ne bloque ni
                    // l'archivage, ni la restauration, ni le changement de stade de cette bande (le client le renomme).
                    'code' => array_merge(['required', 'string', 'max:50'], $existante !== null && trim((string) $existante->code) === trim((string) ($donnees['code'] ?? ''))
                        ? [] : [\App\Rules\UniqueNormalise::bande($existante?->id, depuisPoste: true)]),
                    'species_id' => ['required', 'uuid', 'exists:livestock_species,id'],
                    'stage' => ['required', 'in:'.implode(',', array_keys(LivestockLot::stadesPourEspece($espece?->code)))],
                    'created_date' => ['required', 'date'],
                    'initial_quantity' => ['required', 'integer', 'min:1'],
                    'acquisition_cost' => ['nullable', 'numeric', 'min:0'],
                    'product_id' => ['nullable', 'uuid', 'exists:products,id'],
                    'status' => ['sometimes', 'in:actif,cloture'],
                    'is_active' => ['sometimes', 'boolean'],
                    'effectif_corrige' => ['nullable', 'integer', 'min:0'],
                    // BS-Q7 : geste EXPLICITE de restauration (jamais déduit de `is_active: true`, qui peut venir d'une copie périmée).
                    'restauree' => ['sometimes', 'nullable', 'boolean'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                $archivee = array_key_exists('is_active', $valides) && ! filter_var($valides['is_active'], FILTER_VALIDATE_BOOLEAN);
                $restauree = ! $archivee && filter_var($valides['restauree'] ?? false, FILTER_VALIDATE_BOOLEAN);

                // Ticket UNI : le code ne change jamais, SAUF pour corriger un doublon (code partagé avec une autre bande).
                $renomme = $existante !== null && trim((string) $existante->code) !== $valides['code'];
                if ($renomme && ! $existante->codeEstEnDoublon()) {
                    $rejected[] = ['id' => $id, 'reason' => "Le code d'une bande ne se modifie jamais après sa création."];

                    continue;
                }

                // Une seule transaction par ligne : une création suivie d'un refus n'écrit rien.
                DB::transaction(function () use ($saisie, $valides, $existante, $archivee, $restauree, $renomme) {
                    if ($existante === null) {
                        $saisie->creer([
                            'code' => $valides['code'], 'species_id' => $valides['species_id'], 'stage' => $valides['stage'],
                            'created_date' => $valides['created_date'], 'quantity' => $valides['initial_quantity'],
                            'acquisition_cost' => $valides['acquisition_cost'] ?? null, 'product_id' => $valides['product_id'] ?? null,
                        ], $valides['id']);
                        // Créée puis clôturée ou corrigée avant tout envoi : les deux gestes se rejouent dans l'ordre.
                        if (($valides['status'] ?? 'actif') !== 'actif' || ($valides['effectif_corrige'] ?? null) !== null) {
                            $saisie->modifier($valides['id'], [
                                'stage' => $valides['stage'],
                                'status' => $valides['status'] ?? 'actif',
                                'current_quantity' => $valides['effectif_corrige'] ?? null,
                            ]);
                        }
                        if ($archivee) {
                            $saisie->archiver($valides['id']);
                        }
                    } elseif ($archivee) {
                        // BS-Q3 : la bande doit être vidée AVANT d'être archivée. Une correction d'effectif envoyée avec
                        // l'archivage (bande vidée au poste) se joue d'abord, comme au web (Modifier, puis Archiver).
                        if ((($valides['effectif_corrige'] ?? null) !== null || $renomme) && $existante->is_active) {
                            $saisie->modifier($valides['id'], [
                                'stage' => $valides['stage'],
                                'status' => $valides['status'] ?? $existante->status,
                                'current_quantity' => $valides['effectif_corrige'] ?? null,
                                'code' => $valides['code'],
                            ]);
                        }
                        $saisie->archiver($valides['id']);
                    } else {
                        // BS-Q7 : la restauration est un geste explicite du poste, jouée avant la modification éventuelle.
                        if ($restauree) {
                            $saisie->restaurer($valides['id']);
                        }
                        $saisie->modifier($valides['id'], [
                            'stage' => $valides['stage'],
                            'status' => $valides['status'] ?? $existante->status,
                            'current_quantity' => $valides['effectif_corrige'] ?? null,
                            'code' => $valides['code'],
                        ]);
                    }
                });

                $accepted[] = $valides['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Ticket BS3 (décision BS-Q1 du 21/10/2026) — reproducteurs nominatifs créés, modifiés ou sortis au poste. `animals`
     * était un référentiel en lecture seule : c'est maintenant une table MIXTE (tirée ET saisie), jouée par
     * `SaisieReproducteurAction` — le point de passage de l'écran web « Registre des Reproducteurs » (mêmes règles,
     * mêmes messages, même audit).
     *
     * ⚠️ IDENTIFIER UN SUJET N'EST PAS LE FAIRE ENTRER : aucune écriture ne touche l'effectif d'une bande (le sujet est
     * déjà compté dans sa bande, la fiche journalière fait foi) — comme au web, aucune cascade.
     *
     * Idempotent : un renvoi identique n'écrit rien ; la même sortie rejouée est acquittée sans trace ; une sortie
     * différente d'un sujet déjà sorti est refusée. La catégorie est toujours « reproducteur » (seul suivi nominatif).
     *
     * @return array{accepted: array<int, string>, rejected: array<int, array{id: mixed, reason: string}>}
     */
    private function pushAnimals(array $sujets): array
    {
        $accepted = [];
        $rejected = [];
        $saisie = app(\App\Actions\SaisieReproducteurAction::class);

        foreach ($sujets as $donnees) {
            $id = is_array($donnees) ? ($donnees['id'] ?? null) : null;

            try {
                $donnees = is_array($donnees) ? $donnees : [];
                $existant = is_string($id) && \Illuminate\Support\Str::isUuid($id) ? Animal::find($id) : null;
                $sorti = ($donnees['status'] ?? 'actif') !== 'actif';

                $valides = validator($donnees, [
                    'id' => ['required', 'uuid'],
                    'identifier' => ['required', 'string', 'max:50', \Illuminate\Validation\Rule::unique('animals', 'identifier')->ignore($existant?->id)],
                    'species_id' => ['required', 'uuid', 'exists:livestock_species,id'],
                    'lot_id' => ['nullable', 'uuid', 'exists:livestock_lots,id'],
                    'sex' => ['required', 'in:M,F'],
                    'breed' => ['nullable', 'string', 'max:100'],
                    'birth_date' => ['nullable', 'date', 'before_or_equal:today'],
                    'entry_date' => ['required', 'date', 'before_or_equal:today'],
                    'origin' => ['nullable', 'string', 'max:150'],
                    'cage' => ['nullable', 'string', 'max:30'],
                    'status' => ['sometimes', 'in:actif,reforme,vendu,mort'],
                    'exit_date' => [\Illuminate\Validation\Rule::requiredIf($sorti), 'nullable', 'date', 'before_or_equal:today'],
                    'exit_reason' => ['nullable', 'string', 'max:150'],
                ], MotifsRefusPush::messages(), array_merge(MotifsRefusPush::attributs(), [
                    'identifier' => 'identifiant', 'sex' => 'sexe', 'breed' => 'race', 'birth_date' => 'date de naissance',
                    'entry_date' => "date d'entrée", 'origin' => 'origine', 'cage' => 'cage', 'status' => 'statut',
                    'exit_date' => 'date de sortie', 'exit_reason' => 'motif de sortie',
                ]))->validate();

                // Une seule transaction par ligne : une création suivie d'un refus de sortie n'écrit rien.
                DB::transaction(function () use ($saisie, $valides, $existant, $sorti) {
                    $fiche = Arr::only($valides, ['identifier', 'species_id', 'lot_id', 'sex', 'breed', 'birth_date', 'entry_date', 'origin', 'cage']);

                    if ($existant === null) {
                        $saisie->enregistrer($fiche, $valides['id']);
                    } else {
                        $saisie->modifier($valides['id'], $fiche);
                    }

                    if ($sorti) {
                        $saisie->sortir($valides['id'], [
                            'status' => $valides['status'], 'exit_date' => $valides['exit_date'], 'exit_reason' => $valides['exit_reason'] ?? null,
                        ]);
                    }
                });

                $accepted[] = $valides['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Ticket 15.46 — transferts entre bandes créés ou annulés au poste. Jamais fusionnés : un transfert nouveau
     * est REJOUÉ par `TransferBetweenLotsAction` (mêmes contrôles d'effectif que l'écran web, fiches et cascade
     * recalculées par le serveur) ; un transfert connu n'accepte qu'une annulation (`is_active: false`).
     *
     * @return array{accepted: array<int, string>, rejected: array<int, array{id: mixed, reason: string}>}
     */
    private function pushTransferts(array $transferts, $utilisateur, ?string $deviceId): array
    {
        $accepted = [];
        $rejected = [];
        $action = app(TransferBetweenLotsAction::class);

        foreach ($transferts as $donnees) {
            $id = is_array($donnees) ? ($donnees['id'] ?? null) : null;

            try {
                $valides = validator(is_array($donnees) ? $donnees : [], [
                    'id' => ['required', 'uuid'],
                    'source_lot_id' => ['required', 'uuid', 'exists:livestock_lots,id'],
                    'target_lot_id' => ['required', 'uuid', 'exists:livestock_lots,id'],
                    'transfer_date' => ['required', 'date', 'before_or_equal:today'],
                    'quantity' => ['required', 'integer', 'min:1'],
                    'categorie' => ['nullable', 'in:repro,sevre,jeune'],
                    'constitution' => ['nullable', 'boolean'],
                    'motif' => ['nullable', 'string', 'max:255'],
                    'is_active' => ['nullable', 'boolean'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                $existant = LivestockTransfer::find($valides['id']);
                $actif = (bool) ($valides['is_active'] ?? true);

                if ($existant !== null) {
                    if (! $actif && $existant->is_active) {
                        $action->annuler($existant);
                    }
                    $accepted[] = $existant->id;

                    continue;
                }

                if (! $actif) {
                    // Créé puis annulé au poste avant tout envoi : rien à rejouer.
                    $accepted[] = $valides['id'];

                    continue;
                }

                $action->execute(Arr::only($valides, [
                    'source_lot_id', 'target_lot_id', 'transfer_date', 'quantity', 'categorie', 'constitution', 'motif',
                ]), $utilisateur, $deviceId, $valides['id']);

                $accepted[] = $valides['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /** Ticket S1 — champs d'une vente que le poste a le droit d'écrire (tous validés dans `pushSales`). */
    private const VENTE_CHAMPS_DU_POSTE = [
        'customer_id', 'payment_mode', 'subtotal', 'discount', 'total',
        'cash_received', 'change_due', 'status', 'sold_at',
    ];

    /** Ticket S1 — champs d'une ligne de vente que le poste a le droit d'écrire. */
    private const LIGNE_DE_VENTE_CHAMPS_DU_POSTE = [
        'product_id', 'lot_id', 'qty', 'unit_price', 'manual_total_amount',
    ];

    private function pushSales(array $sales, array $fichesRecues = []): array
    {
        $accepted = [];
        $rejected = [];

        foreach ($sales as $saleData) {
            // ⚠️ TICKET 15.38 — `discount` est NOT NULL DEFAULT 0 : `null` = clé absente = aucune remise.
            $saleData = $this->sansNullSurColonnesNotNull($saleData, ['discount']);

            // 🔴→✅ TICKET AV2 — LA DEMANDE D'ANNULATION D'UN POSTE. Le bouton « Annuler » de l'historique des ventes du
            // poste passe la vente à `annulee` et la renvoie : le serveur fait l'effet (`AnnulerVenteAction`, celle de
            // `HistoriqueVentes::cancelSale()` : stock réintégré, statut, audit), une seule fois. Une vente CONNUE est
            // annulée ; une vente INCONNUE (annulée avant son premier envoi) est reçue comme vendue, avec tous ses
            // effets, PUIS annulée — le même chemin que le web (vendre, puis annuler), jamais un statut posé sans effet.
            $aAnnuler = is_array($saleData) && ($saleData['status'] ?? null) === 'annulee';
            if ($aAnnuler) {
                $saleData['status'] = 'validee';
            }

            try {
                // ⚠️⚠️ TICKET 14.70 — LE CONTENU DES LIGNES EST ENFIN EXAMINE.
                // Les lignes etaient creees par assignation de masse
                // (`SaleLine::create(array_merge(...))`) SANS AUCUN CONTROLE :
                // un produit inexistant levait une violation de cle etrangere
                // NON RATTRAPEE — donc 500 pour la requete ENTIERE, emportant
                // les fiches d'elevage et les depenses du meme envoi (meme
                // defaut que le doublon de fiche, ticket 14.69).
                $validated = validator($saleData, [
                    'id' => ['required', 'uuid', 'unique:sales,id'],
                    // 🔴→✅ TICKET S1 — mode de paiement borné aux valeurs de la colonne (enum) : une autre valeur
                    // échouait en base au lieu d'un refus motivé.
                    'payment_mode' => ['required', 'string', 'in:especes,mobile_money,virement,credit,avance'],
                    'customer_id' => ['nullable', 'uuid', 'exists:customers,id'],
                    'cash_received' => ['nullable', 'numeric', 'min:0'],
                    'change_due' => ['nullable', 'numeric', 'min:0'],
                    'status' => ['nullable', 'in:validee,annulee'],
                    // 🔴→✅ TICKET 15.38 — `sales.subtotal` est NOT NULL SANS défaut : `nullable` laissait passer
                    // un 500 pour l'envoi entier (une clé omise le donnait déjà). Refus motivé de CETTE vente.
                    'subtotal' => ['required', 'numeric', 'min:0'],
                    'discount' => ['nullable', 'numeric', 'min:0'],
                    'total' => ['required', 'numeric', 'min:0'],
                    // 🔴→✅ TICKET 14.71 — DATE REELLE DE LA VENTE. Sans elle,
                    // le serveur datait tout du TIRAGE : ecriture SYSCOHADA
                    // sur la mauvaise periode, fiche d'elevage du mauvais
                    // jour. `before_or_equal:now` interdit la vente datee du
                    // futur ; `nullable` laisse passer un poste ancien, qui
                    // retombe alors sur l'ancien comportement plutot que de
                    // voir son envoi rejete.
                    'sold_at' => ['nullable', 'date', 'before_or_equal:now'],
                    'lines' => ['required', 'array', 'min:1'],
                    'lines.*.product_id' => ['required', 'uuid', 'exists:products,id'],
                    'lines.*.lot_id' => ['nullable', 'uuid', 'exists:livestock_lots,id'],
                    // ⚠️ QUANTITE STRICTEMENT POSITIVE : une ligne a zero ou
                    // negative ferait REMONTER le stock sur une vente.
                    'lines.*.qty' => ['required', 'numeric', 'gt:0'],
                    // 🔴→✅ TICKET 15.38 — `sale_lines.unit_price` est NOT NULL SANS défaut (même défaut que le sous-total).
                    'lines.*.unit_price' => ['required', 'numeric', 'min:0'],
                    // ⚠️ SOURCE DE VERITE DU MONTANT (Document 01 §6.7), et
                    // colonne NOT NULL : l'omettre levait une violation de
                    // contrainte, donc un 500 global.
                    'lines.*.manual_total_amount' => ['required', 'numeric', 'min:0'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                $this->verifierCoherenceDuTotal($saleData);

                // 🔴→✅ TICKET 15.30 — UNE VENTE DATÉE EST JUGÉE SUR SA DATE, AVANT TOUT EFFET.
                // Futur, mois clôturé (verrou du Journal), exercice absent ou clos : refus MOTIVÉ,
                // pour cette vente seule. Placé APRÈS la validation (`unique:sales,id`) : une vente
                // déjà synchronisée reste un succès silencieux même si son mois a été clôturé depuis.
                // Sans `sold_at` (poste ancien) la date de réception fait foi et seul le rattrapage
                // des exceptions comptables, plus bas, protège l'envoi.
                if (! empty($validated['sold_at'])) {
                    app(VerifySaleDateAction::class)->execute($validated['sold_at']);
                }

                DB::transaction(function () use ($validated, $saleData, $fichesRecues, $aAnnuler) {
                    // ⚠️ Même contrainte que LivestockDailyEntry ci-dessus :
                    // 'id' n'est pas fillable sur Sale — assignation
                    // explicite pour préserver réellement l'UUID généré
                    // côté client Flutter au moment de la vente hors-ligne.
                    $sale = new Sale();
                    $sale->id = $validated['id'];
                    // 🔴→✅ TICKET S1 — SEULS LES CHAMPS VALIDÉS SONT REPRIS. `fill()` recevait toute la vente
                    // envoyée : `mecef_status`, `mecef_qr_ref` ou `accounting_entry_id` passaient tels quels, et
                    // une ligne pouvait se rattacher à une autre vente (son `sale_id` écrasait celui du serveur).
                    // `status` est NOT NULL avec défaut : absent ou `null`, il garde son défaut (`validee`).
                    $sale->fill(array_filter(
                        Arr::only($saleData, self::VENTE_CHAMPS_DU_POSTE),
                        fn ($valeur, $champ) => $champ !== 'status' || $valeur !== null,
                        ARRAY_FILTER_USE_BOTH,
                    ));
                    $sale->save();

                    foreach ($saleData['lines'] as $line) {
                        SaleLine::create(array_merge(
                            Arr::only($line, self::LIGNE_DE_VENTE_CHAMPS_DU_POSTE),
                            ['sale_id' => $sale->id],
                        ));
                    }

                    // 🔴→✅ TICKET 14.53 — LES QUATRE EFFETS D'UNE VENTE.
                    //
                    // Ce canal n'insérait QUE la vente et ses lignes. Une vente
                    // encaissée hors ligne au comptoir puis remontée arrivait
                    // donc en base comme une ligne morte : stock inchangé,
                    // fiche d'élevage inchangée, AUCUNE écriture comptable,
                    // AUCUN encaissement. Bilan, Compte de Résultat, stock et
                    // effectif de bande étaient faux — silencieusement, et
                    // d'autant plus longtemps que le poste reste hors ligne.
                    //
                    // ⚠️ LES MÊMES ACTIONS QUE LA CAISSE WEB, jamais une
                    // seconde implémentation : c'est ce qui garantit qu'une
                    // vente produit le même effet quel que soit le chemin
                    // qu'elle a pris pour arriver.
                    foreach ($saleData['lines'] as $line) {
                        $product = Product::find($line['product_id'] ?? null);

                        if ($product) {
                            app(AdjustStockAction::class)->execute(
                                $product,
                                -abs((float) ($line['qty'] ?? 0)),
                                'sale',
                                $sale->id,
                                // 15.30 : le mouvement porte le jour de la VENTE, pas celui du tirage
                                // (null = poste ancien : AdjustStockAction retombe sur now()).
                                $sale->sold_at,
                            );
                        }
                    }

                    // ⚠️ TICKET 14.71 — LE JOUR DE LA VENTE, PAS CELUI DU
                    // TIRAGE. Sans ce second argument l'action retombe sur
                    // `now()` : les tetes vendues le 28/07 hors ligne etaient
                    // deduites de la fiche du 02/08, et celle du 28/07 restait
                    // incoherente avec la sortie reelle des animaux.
                    //
                    // 🔴→✅ TICKET 15.30 — PAS DE DOUBLE COMPTAGE. Le poste répercute la vente sur
                    // SA fiche du jour (`vente = N`) puis envoie la fiche ET la vente. Le serveur
                    // traite les fiches d'abord (dernier écrivain gagne) : la fiche reçue porte déjà
                    // N, et l'action y rajoutait N une seconde fois (2N, effectif de bande faux de N).
                    // Les fiches (bande, jour) ACCEPTÉES dans ce même envoi sont donc signalées à
                    // l'action : elle n'y incrémente plus `vente`. Une fiche rejetée n'exempte rien.
                    app(RecordSaleOnFicheElevageAction::class)->execute(
                        $saleData['lines'],
                        $sale->date_effective?->format('Y-m-d'),
                        $fichesRecues,
                    );
                    app(RecordSaleAccountingEntryAction::class)->execute($sale->fresh('lines'));
                    app(CreditTreasuryForSaleAction::class)->execute($sale);

                    // 🔴→✅ TICKET 15.19 — UNE VENTE À CRÉDIT CRÉE SA CRÉANCE, ICI COMME À LA CAISSE.
                    // Ce canal passait l'écriture D 411 mais ne créait AUCUNE ligne `receivables` :
                    // seule `PosInterface` le faisait. La créance n'existait donc ni au suivi des
                    // dettes, ni à la balance âgée, ni au tirage — et aucune avance ni aucun
                    // règlement ne pouvait la viser. Mêmes valeurs que la caisse (échéance à 30
                    // jours), comptées depuis la date de la VENTE et non du tirage.
                    if ($sale->payment_mode === 'credit' && $sale->customer_id) {
                        \App\Models\Receivable::create([
                            'customer_id' => $sale->customer_id,
                            'sale_id' => $sale->id,
                            'amount' => $sale->total,
                            'amount_paid' => 0,
                            'due_date' => ($sale->date_effective ?? now())->copy()->addDays(30)->toDateString(),
                            'status' => 'en_cours',
                        ]);
                    }

                    // ⚠️⚠️ TICKET 14.68 — FILET SANITAIRE A LA RECEPTION. Le
                    // poste refuse deja la vente d'une bande sous remanence,
                    // mais SEULEMENT avec les remanences qu'il a tirees : un
                    // traitement enregistre sur le web ce matin est invisible
                    // d'un poste qui n'a pas synchronise depuis hier. Le
                    // serveur est alors le seul a pouvoir s'en apercevoir.
                    //
                    // ⚠️ LA VENTE EST ENREGISTREE, PAS REFUSEE : elle a deja eu
                    // lieu. La refuser retirerait des livres une recette
                    // encaissee ET ferait perdre la tracabilite de l'acheteur,
                    // seule base d'un rappel sanitaire.
                    app(FlagSaleUnderWithdrawalAction::class)->execute($sale->fresh('lines'));

                    // Ticket H14 (D-SYNC-4) — une vente qui fait passer un stock sous zéro est ACCEPTÉE et SIGNALÉE à
                    // l'administrateur, jamais refusée ni passée sous silence.
                    app(\App\Actions\FlagNegativeStockFromSyncAction::class)->execute($sale->fresh('lines'));

                    if ($aAnnuler) {
                        app(\App\Actions\AnnulerVenteAction::class)->execute($sale->fresh('lines'));
                    }

                    // 🔴→✅ TICKET 14.80 — LA NORMALISATION FISCALE MANQUAIT : une vente encaissée hors ligne arrivait
                    // en base avec `mecef_status` NUL, jamais déclarée à la DGI. ⚠️ TICKET S-T13 : elle est facturée
                    // APRÈS la transaction de l'envoi (`push`, `ventesAFacturer`), jamais dans un essai qui peut être
                    // annulé puis rejoué. Un échec ne perd pas la vente : `erreur`, retransmise depuis l'écran Facturation.
                });

                $accepted[] = $validated['id'];
                // Une vente reçue annulée n'a pas à être normalisée auprès de la DGI.
                if (! $aAnnuler) {
                    $this->ventesAFacturer[] = $validated['id'];
                }
            } catch (ValidationException $e) {
                // 'unique:sales,id' échoue si cette vente a déjà été
                // synchronisée précédemment — traité comme un succès
                // silencieux (déjà là), jamais une erreur, pour permettre
                // un push répété sans risque en cas de coupure réseau.
                if (isset($saleData['id']) && Sale::where('id', $saleData['id'])->exists()) {
                    // Ticket AV2 — vente CONNUE renvoyée annulée : la demande d'annulation est rejouée (idempotente).
                    if ($aAnnuler) {
                        try {
                            app(\App\Actions\AnnulerVenteAction::class)->execute(Sale::with('lines')->find($saleData['id']));
                        } catch (NoOpenFiscalYearException|ClosedFiscalYearException $e) {
                            $rejected[] = ['id' => $saleData['id'], 'reason' => 'Annulation refusée : '.$e->getMessage()];

                            continue;
                        }
                    }
                    $accepted[] = $saleData['id'];
                } else {
                    $rejected[] = ['id' => $saleData['id'] ?? null, 'reason' => MotifsRefusPush::motif($e)];
                    $this->retirerDesFichesPorteuses($saleData, $fichesRecues);
                }
            } catch (SaleDateRefusedException $e) {
                // 🔴→✅ TICKET 15.30 — date refusée par `VerifySaleDateAction` : rejet MOTIVÉ de cette
                // vente seule. Le poste la passe en `conflict` avec ce motif, au lieu de la rejouer.
                $rejected[] = ['id' => $saleData['id'] ?? null, 'reason' => $e->getMessage()];
                $this->retirerDesFichesPorteuses($saleData, $fichesRecues);
            } catch (NoOpenFiscalYearException|ClosedFiscalYearException $e) {
                // 🔴→✅ TICKET 15.30 — ANCIEN DÉFAUT : seule `ValidationException` était rattrapée ; un
                // exercice absent ou clos levé par `AccountingEntryService::record` (via
                // `RecordSaleAccountingEntryAction`) partait en 500 pour l'envoi ENTIER, que le poste
                // rejouait en boucle, emportant fiches et autres ventes. Même règle que les achats,
                // avances et retours. La transaction ayant été annulée, ni stock, ni fiche, ni caisse
                // n'ont bougé.
                // Ticket EX5 (R4) — même texte que le refus d'une vente datée (`VerifySaleDateAction::prefixe`).
                $rejected[] = ['id' => $saleData['id'] ?? null, 'reason' => \App\Actions\VerifySaleDateAction::prefixe($e->getMessage())];
                $this->retirerDesFichesPorteuses($saleData, $fichesRecues);
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * 🔴→✅ Ticket S-T9 — UNE VENTE REFUSÉE N'EST PAS PORTÉE PAR LA FICHE CRÉÉE DANS LE MÊME ENVOI.
     *
     * Le poste répercute chaque vente sur la fiche du jour AVANT d'envoyer : une fiche créée par cet envoi arrive avec
     * la vente de ses sujets (règle 15.30 : la vente n'est alors pas comptée une seconde fois). Si la vente est
     * refusée (mois clôturé, exercice clos, total incohérent…), la fiche gardait ces sujets « vendus » alors qu'aucune
     * vente n'existe : effectif faux, et la vente relancée plus tard les recomptait. Ils en sont retirés ici, dans la
     * même requête, et la cascade suit.
     *
     * @param  array<string, true>  $fichesRecues
     */
    private function retirerDesFichesPorteuses(mixed $saleData, array $fichesRecues): void
    {
        if (! is_array($saleData) || $fichesRecues === [] || ! is_array($saleData['lines'] ?? null)) {
            return;
        }

        $jour = rescue(fn () => Carbon::parse($saleData['sold_at'] ?? 'now')->format('Y-m-d'), null, false);
        if ($jour === null) {
            return;
        }

        foreach ($saleData['lines'] as $ligne) {
            $lot = is_array($ligne) ? ($ligne['lot_id'] ?? null) : null;
            $qte = is_array($ligne) && is_numeric($ligne['qty'] ?? null) ? (int) $ligne['qty'] : 0;
            if (! is_string($lot) || $qte <= 0 || ! isset($fichesRecues[$lot.'|'.$jour])) {
                continue;
            }
            $fiche = LivestockDailyEntry::where('lot_id', $lot)->whereDate('entry_date', $jour)->first();
            if ($fiche === null) {
                continue;
            }
            $fiche->vente = max(0, (int) $fiche->vente - $qte);
            $fiche->effectif_final = $fiche->effectifFinalDepuis($fiche->previousEffectif());
            $fiche->save();
            app(RecordSaleOnFicheElevageAction::class)->recalculerEnCascade($lot, $jour);
        }
    }

    /**
     * Soins vétérinaires saisis hors ligne.
     *
     * ⚠️⚠️ REJOUÉS PAR `RecordVeterinaryCareAction`, JAMAIS INSÉRÉS TELS QUELS.
     * Un soin porte un délai d'attente : c'est lui qui bloque la bande à la
     * vente. Insérer le seul registre laisserait la bande VENDABLE alors qu'un
     * traitement vient d'être administré — la ferme écoulerait une viande
     * porteuse de résidus d'antibiotiques, et rien ne le signalerait.
     *
     * ⚠️ Un renvoi après coupure ne doit pas empiler les rémanences : un soin
     * déjà connu est un succès silencieux, comme pour les ventes.
     */
    private function pushVeterinaryRecords(array $soins): array
    {
        $accepted = [];
        $rejected = [];

        foreach ($soins as $soin) {
            try {
                // 🔴→✅ TICKET U3 (décision client D-U3 du 19/10/2026) — L'ARCHIVAGE D'UN SOIN SE FAIT AU POSTE COMME AU
                // WEB (`SoinsVaccinsHub::archiveSoin()` : `is_active = false` + `veterinary_record.archived`). Un soin
                // CONNU n'accepte que cela : `{id, is_active: false}` ou la ligne complète, le reste est ignoré (un soin
                // n'est jamais modifié, comme au web). ARCHIVAGE LOGIQUE SEULEMENT : `is_active: true` sur un soin
                // archivé ne le restaure pas (la restauration passe par la Corbeille du web), et la rémanence créée
                // par le soin reste en vigueur, exactement comme après `archiveSoin()`. Droit `manage-elevage`
                // (`PERMISSION_PAR_TABLE`), celui du web.
                $existant = isset($soin['id']) && is_string($soin['id']) ? VeterinaryRecord::find($soin['id']) : null;

                if ($existant !== null) {
                    $v = validator($soin, [
                        'id' => ['required', 'uuid'],
                        'is_active' => ['sometimes', 'boolean'],
                    ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                    if (array_key_exists('is_active', $v) && ! filter_var($v['is_active'], FILTER_VALIDATE_BOOLEAN) && $existant->is_active) {
                        $existant->update(['is_active' => false]);
                        AuditLog::record('veterinary_record.archived', 'elevage');
                    }
                    $accepted[] = $v['id'];

                    continue;
                }

                $validated = validator($soin, [
                    'id' => ['required', 'uuid'],
                    'lot_id' => ['required', 'uuid', 'exists:livestock_lots,id'],
                    'action_type' => ['required', 'string', 'max:100'],
                    'record_date' => ['required', 'date'],
                    'withdrawal_days' => ['nullable', 'integer', 'min:0'],
                    // 🔴→✅ TICKET S1 — champs transmis tels quels à `RecordVeterinaryCareAction` sans contrôle.
                    'product_used' => ['nullable', 'string', 'max:150'],
                    'dose' => ['nullable', 'string', 'max:100'],
                    'vet_name' => ['nullable', 'string', 'max:150'],
                    'symptomes' => ['nullable', 'string', 'max:5000'],
                    'gravite' => ['nullable', 'in:legere,moderee,severe'],
                    'cost' => ['nullable', 'numeric', 'min:0'],
                    // Ticket U3 — un soin saisi PUIS archivé hors ligne arrive archivé.
                    'is_active' => ['sometimes', 'boolean'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                $archive = array_key_exists('is_active', $validated) && ! filter_var($validated['is_active'], FILTER_VALIDATE_BOOLEAN);

                // Ticket S1 — seuls les champs validés partent : ni `daily_entry_id` venu du poste. Ticket U3 : le soin
                // est CRÉÉ (avec sa rémanence, comme `saveSoin()`), puis archivé comme par `archiveSoin()`.
                $cree = app(RecordVeterinaryCareAction::class)->execute(
                    Arr::except($validated, ['withdrawal_days', 'is_active']),
                    (int) ($soin['withdrawal_days'] ?? 0),
                );
                if ($archive) {
                    $cree->update(['is_active' => false]);
                    AuditLog::record('veterinary_record.archived', 'elevage');
                }

                $accepted[] = $validated['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $soin['id'] ?? null, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Ticket 15.20 — cette sortie de stock désigne-t-elle un retour fournisseur (que le serveur décrémente déjà) ?
     *
     * @param  array<int, string>  $identifiantsDeRetours  UUID des retours et ids d'achats du paquet
     */
    private function sortieDeRetourFournisseur(array $ajustement, ?string $clientRef, array $identifiantsDeRetours): bool
    {
        if (in_array($ajustement['reference_type'], ['purchase_return', 'retour_fournisseur'], true)) {
            return true;
        }

        if ($clientRef === null) {
            return false;
        }

        return in_array($clientRef, $identifiantsDeRetours, true)
            || \App\Models\PurchaseReturn::where('return_batch_id', $clientRef)->orWhere('purchase_id', $clientRef)->exists();
    }

    /**
     * Mouvements de stock : JAMAIS acceptés tels quels. Réappliqués via
     * `AdjustStockAction` (ticket 6.1, seul point d'entrée réel) — le
     * solde final est donc TOUJOURS recalculé server-side depuis l'état
     * réel du produit au moment du push, jamais un delta hors-ligne
     * appliqué aveuglément (double décrément non détecté sinon, exactement
     * le risque déjà documenté dans `LARAVEL_SYNC_FLUTTER.md`).
     */
    private function pushStockAdjustments(array $adjustments, array $identifiantsDeRetours = []): array
    {
        $accepted = [];
        $rejected = [];

        foreach ($adjustments as $adj) {
            try {
                $validated = validator($adj, [
                    // 🔴→✅ TICKET 14.74 — L'IDENTIFIANT CLIENT DE L'AJUSTEMENT.
                    //
                    // ⚠️⚠️ CE CANAL ACQUITTAIT AVEC LE `product_id`. Le poste,
                    // lui, rapproche l'accuse de reception de l'identifiant de
                    // SA ligne : il ne se reconnaissait donc jamais dedans,
                    // laissait l'ajustement en attente, et le RENVOYAIT a
                    // chaque synchronisation. Chaque renvoi rejouait le
                    // decrement de stock ET passait une nouvelle ecriture de
                    // perte. Un manquant de 5 sacs constate une fois en
                    // retirait 5 de plus a chaque tirage, indefiniment.
                    //
                    // Le defaut n'avait jamais tire a blanc : AUCUN ecran du
                    // poste ne creait d'ajustement (corrige au ticket F0.38).
                    // ⚠️ `string` ET NON `uuid` : refuser l'ajustement parce
                    // que sa reference cliente n'est pas un UUID bloquerait
                    // une donnee valide pour un detail de forme. Le poste
                    // envoie un UUID ; la suite de tests de ce point d'entree
                    // utilise, elle, une chaine courte depuis l'origine.
                    'client_ref' => ['nullable', 'string', 'max:64'],
                    'product_id' => ['required', 'uuid', 'exists:products,id'],
                    'type' => ['required', 'in:entree,sortie'],
                    'quantity' => ['required', 'numeric', 'min:0.01'],
                    'reference_type' => ['required', 'string'],
                    'reason' => ['nullable', 'string'],
                    // Ticket U10 — date du mouvement, lue pour un « Ajout Manuel » seulement (voir plus bas).
                    'movement_date' => ['nullable', 'date'],
                    // Ticket S-T10 — inventaire du poste : la QUANTITÉ COMPTÉE et l'INSTANT du comptage (ISO 8601 avec
                    // fuseau). Absents (poste ancien) : l'écart local `type` + `quantity` est appliqué comme avant.
                    'counted_quantity' => ['nullable', 'numeric', 'min:0'],
                    'counted_at' => ['nullable', 'required_with:counted_quantity', 'date'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                // 🔴→✅ TICKET U10 — « AJOUTER STOCK » SAISI AU POSTE (`reference_type = manual_addition`).
                //
                // ⚠️⚠️ MÊMES RÈGLES QUE `GestionStocks::submitAjouterStock()` : une ENTRÉE, une quantité ENTIÈRE d'au
                // moins 1, une date obligatoire — et c'est CETTE date qui date le mouvement (`Carbon::parse($addDate)`
                // au web), pas l'instant de réception. Un ajout du 3 reçu le 5 compte au 3 dans la rotation et le
                // grand livre, comme s'il avait été saisi au web. Les autres ajustements gardent leur règle (rejoués
                // à la réception, `movement_date` ignorée) : l'inventaire du web est daté de son enregistrement.
                $ajoutManuel = $validated['reference_type'] === 'manual_addition';
                if ($ajoutManuel) {
                    validator($adj, [
                        'type' => ['required', 'in:entree'],
                        'quantity' => ['required', 'integer', 'min:1'],
                        'movement_date' => ['required', 'date'],
                    ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();
                }

                $clientRef = $validated['client_ref'] ?? null;

                // 🔴→✅ TICKET 15.20 — UN RETOUR FOURNISSEUR NE SE DÉCRÉMENTE PAS DEUX FOIS. Le serveur décrémente
                // lui-même le stock d'un retour (`PurchaseReturnService`, `purchase_returns`) ; un poste qui joindrait
                // en plus sa propre sortie « retour fournisseur » ferait descendre le stock deux fois, sans erreur.
                // Une sortie désignée comme retour (type de référence, ou référence = id d'un retour / d'un achat
                // retourné, du paquet ou déjà reçu) est donc REFUSÉE avec son motif. Une sortie sans rapport avec un
                // retour (perte d'inventaire) s'applique normalement.
                if ($validated['type'] === 'sortie' && $this->sortieDeRetourFournisseur($validated, $clientRef, $identifiantsDeRetours)) {
                    $rejected[] = [
                        'id' => $clientRef,
                        'client_ref' => $clientRef,
                        'reason' => "Cette sortie désigne un retour fournisseur : le serveur décrémente lui-même le stock d'un retour (purchase_returns). Ne pas l'envoyer en ajustement de stock.",
                    ];

                    continue;
                }

                // ⚠️ IDEMPOTENCE : deja applique, on acquitte sans rien
                // rejouer. `stock_movements.reference_id` porte l'identifiant
                // de la ligne du poste, ce qui rend le renvoi inoffensif meme
                // si l'accuse s'est perdu en route.
                if ($clientRef !== null && \App\Models\StockMovement::where('reference_id', $clientRef)->exists()) {
                    $accepted[] = $clientRef;

                    continue;
                }

                $product = Product::findOrFail($validated['product_id']);
                $delta = $validated['type'] === 'entree' ? $validated['quantity'] : -$validated['quantity'];
                $dateDuMouvement = $ajoutManuel ? \Carbon\Carbon::parse($validated['movement_date']) : null;

                // 🔴→✅ TICKET S-T10 — L'ÉCART D'UN INVENTAIRE EST CALCULÉ ICI, CONTRE LE STOCK DU SERVEUR À L'INSTANT
                // DU COMPTAGE (`InventaireAuComptageService`), jamais repris du poste. L'écart local (`type`,
                // `quantity`) était calculé sur un stock local qui ignorait les ventes faites ailleurs et pas encore
                // descendues : chacune était décomptée deux fois. Le poste ancien, qui n'envoie que l'écart, garde
                // l'ancien comportement (bloc suivant inchangé).
                if (! $ajoutManuel && isset($validated['counted_quantity'])) {
                    $comptage = app(\App\Services\InventaireAuComptageService::class);
                    $instant = $comptage->instantDuComptage((string) $validated['counted_at']);
                    // ⚠️ Ligne du produit verrouillée jusqu'à la fin de l'envoi (une transaction, S-T9) : une vente
                    // reçue en même temps ne glisse pas entre la lecture du stock et l'application de l'écart.
                    $product = Product::query()->lockForUpdate()->findOrFail($validated['product_id']);
                    $evaluation = $comptage->evaluer($product, (float) $validated['counted_quantity'], $instant);

                    if ($evaluation['depasse'] || $evaluation['ecart'] == 0) {
                        // Rien à ajuster (le web dit « Aucun écart détecté ») ou comptage remplacé par un inventaire
                        // plus récent : acquitté, aucun mouvement, aucune écriture — la trace reste à l'audit.
                        AuditLog::record($evaluation['depasse'] ? 'stock.inventaire_depasse' : 'stock.inventaire_sans_ecart', 'stocks');
                        $accepted[] = $clientRef ?? $validated['product_id'];

                        continue;
                    }

                    $delta = $evaluation['ecart'];
                    $dateDuMouvement = $instant;
                }

                // 🔴→✅ Ticket EX5 — LE MOUVEMENT ET SA PERTE, ENSEMBLE OU PAS DU TOUT (point de sauvegarde par ligne). La
                // perte refusée (aucun exercice ne couvre le jour du comptage) laissait le mouvement écrit, sans sa charge.
                DB::transaction(function () use ($product, $delta, $validated, $clientRef, $dateDuMouvement, $ajoutManuel) {
                    app(AdjustStockAction::class)->execute(
                        product: $product,
                        delta: $delta,
                        referenceType: $validated['reference_type'],
                        // ⚠️ C'est cette trace qui rend le renvoi inoffensif.
                        referenceId: $clientRef,
                        // Ajout manuel : le jour choisi (U10). Inventaire compté (S-T10) : l'instant du comptage, pour
                        // que le grand livre le place avant les mouvements qui l'ont suivi. Sinon : la réception.
                        movementDate: $dateDuMouvement,
                        reason: $validated['reason'] ?? null,
                    );

                    // Ticket U10 — l'ajout manuel du web ne passe AUCUNE écriture (ce n'est pas un écart d'inventaire)
                    // et laisse sa trace d'audit : même chose ici.
                    if ($ajoutManuel) {
                        AuditLog::record('stock.manual_addition', 'stocks');

                        return;
                    }

                    // 🔴→✅ TICKET 14.67 — LA PERTE CONSTATEE HORS LIGNE ENTRE
                    // ENFIN DANS LES LIVRES.
                    //
                    // ⚠️⚠️ Le CDC exige que « toute operation financiere (vente,
                    // achat, paie, **perte**) declenche automatiquement la
                    // generation de l'ecriture ». L'ecran web le fait depuis le
                    // ticket 14.41 ; ce chemin-ci ne le faisait pas. Un manquant
                    // d'inventaire saisi sur un poste hors ligne faisait donc
                    // baisser le stock **sans jamais reduire le resultat** — le
                    // meme defaut que les ventes (14.52), la ponte (14.59) et les
                    // depenses (14.62), sur le quatrieme flux.
                    //
                    // ⚠️ L'Action porte deja la regle et ses garde-fous : un
                    // EXCEDENT ne produit aucune ecriture (ce n'est pas un profit
                    // mais le signe d'une entree non saisie), et un produit sans
                    // PMP est ignore plutot que valorise au hasard.
                    // Ticket EX5 — la perte est datée du COMPTAGE (S-T10 : son instant), comme le mouvement ; un poste ancien
                    // sans `counted_at` garde la date de réception (`$dateDuMouvement` nul).
                    app(RecordStockAdjustmentEntryAction::class)
                        ->execute($product->fresh(), $delta, $validated['reason'] ?? null, $dateDuMouvement);
                });

                // ⚠️ ON ACQUITTE L'IDENTIFIANT DE LA LIGNE DU POSTE. Le repli
                // sur `product_id` etait le defaut : deux ajustements sur le
                // meme produit auraient d'ailleurs porte le meme accuse.
                $accepted[] = $clientRef ?? $validated['product_id'];
            } catch (ValidationException $e) {
                // 🔴→✅ TICKET S-T10 (trouvé par l'essai à plusieurs postes) — LE REFUS PORTE AUSSI `id`. Le poste
                // range un refus sous `id`, comme pour toutes les autres tables ; ce canal ne rendait que
                // `client_ref` : un inventaire refusé restait EN ATTENTE au poste, renvoyé à chaque synchronisation,
                // sans que personne ne voie jamais le motif.
                $rejected[] = ['id' => $adj['client_ref'] ?? null, 'client_ref' => $adj['client_ref'] ?? null, 'reason' => MotifsRefusPush::motif($e)];
            } catch (\Throwable $e) {
                // Ticket U5 : un motif technique du framework (anglais) devient une phrase française.
                $rejected[] = ['id' => $adj['client_ref'] ?? null, 'client_ref' => $adj['client_ref'] ?? null, 'reason' => MessagesErreurFr::pourUtilisateur($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }
}
