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
use App\Exceptions\ClosedFiscalYearException;
use App\Exceptions\NoOpenFiscalYearException;
use App\Models\Animal;
use App\Models\AttestationTemplate;
use App\Models\AuditLog;
use App\Models\LivestockSpecies;
use App\Models\Notification;
use App\Services\AttestationService;
use App\Services\EffectifParCategorieService;
use App\Services\JournalSynchronisationService;
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
use Illuminate\Validation\ValidationException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

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
    ];

    /**
     * GET /api/sync/pull?since=2026-08-11T00:00:00Z
     * Renvoie tout ce qui a changé côté serveur depuis `since`, groupé
     * par table. `since` absent ou vide = synchronisation initiale
     * complète (première connexion d'un appareil).
     */
    public function pull(Request $request): JsonResponse
    {
        $request->validate(['since' => ['nullable', 'date']]);

        $since = $request->filled('since') ? $request->date('since') : null;

        $products = Product::query()->when($since, fn ($q) => $q->where('updated_at', '>', $since))->get();
        $categories = ProductCategory::query()->when($since, fn ($q) => $q->where('updated_at', '>', $since))->get();
        // ⚠️ TICKET F0.14 — LE CODE ESPÈCE ACCOMPAGNE LA BANDE. Le poste n'a
        // pas de table des espèces : sans ce champ, il ne peut pas appliquer
        // le garde-fou « aviculture + stade ponte » qui empêche une ponte
        // d'escargots d'entrer au stock d'œufs de table (ticket 14.59). Il
        // devrait deviner à partir du seul stade — et se tromper.
        $lots = LivestockLot::with('species')
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get()
            ->map(function (LivestockLot $lot) {
                $ligne = $lot->toArray();
                unset($ligne['species']);
                $ligne['species_code'] = $lot->species?->code;

                return $ligne;
            });
        $dailyEntries = LivestockDailyEntry::query()->when($since, fn ($q) => $q->where('updated_at', '>', $since))->get();

        // Ticket 15.46 — transferts entre bandes : source de vérité des colonnes `transfert_*` des fiches (servies
        // ci-dessus avec la fiche). Le poste les affiche et peut en créer ou en annuler hors ligne.
        $transferts = LivestockTransfer::query()
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get(['id', 'source_lot_id', 'target_lot_id', 'transfer_date', 'quantity', 'categorie', 'constitution',
                'motif', 'is_active', 'updated_at']);

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
        $rations = FeedRationStandard::where('is_active', true)
            ->orderBy('species_code')->orderBy('stage_label')->get();

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
        // 🔴→✅ TICKET 14.54 — LE CALENDRIER PROPHYLACTIQUE ET LE REGISTRE
        // DESCENDENT AU POSTE. Sans eux, la fiche d'élevage Desktop ne pouvait
        // afficher ni les traitements PRÉVUS du jour ni ceux déjà administrés :
        // les montrer vides aurait laissé croire à une absence de soin à faire.
        //
        // ⚠️ Le calendrier est servi SANS filtre `since` — une dizaine de
        // lignes qui pilotent un affichage sanitaire, et un poste resté hors
        // ligne depuis une correction proposerait sinon un protocole périmé.
        $prophylaxie = ProphylaxisScheduleStandard::where('is_active', true)
            ->orderBy('species_code')
            ->orderBy('period_label')
            ->get();

        // ⚠️ SANS FILTRE `since` : la liste est courte et le poste doit
        // toujours pouvoir proposer un compte payeur, meme apres un tirage
        // incremental ou rien n'a change.
        $comptesTresorerie = \App\Models\TreasuryAccount::query()
            ->where('is_active', true)
            ->orderBy('label')
            ->get(['id', 'label', 'account_code', 'type', 'balance']);

        $soins = VeterinaryRecord::query()
            ->where('is_active', true)
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get();

        $remanences = VeterinaryWithdrawalPeriod::query()
            ->whereDate('end_date', '>=', now()->toDateString())
            ->orderBy('end_date')
            ->get();

        // Ticket H8b (décision D-H8 du 19/10/2026) — l'infirmerie et le calendrier vétérinaire PLANIFIÉ descendent au
        // poste : sans eux, l'onglet « Suivi Sanitaire » et le calendrier restaient vides hors ligne.
        $infirmerie = \App\Models\InfirmaryRecord::query()
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get();
        $calendrierVeterinaire = \App\Models\VeterinaryCalendarEvent::query()
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get();

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
        $clients = Customer::query()
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->orderBy('name')
            ->get(['id', 'name', 'phone', 'email', 'city', 'credit_limit', 'is_active']);

        // ⚠️ SANS FILTRE `since` POUR CE QUI RESTE DU. Une facture echue il y a
        // trois mois n'a plus bouge depuis : un tirage incremental la
        // manquerait, et c'est precisement celle qu'il faut relancer. Meme
        // raisonnement que les remanences et les cycles en cours.
        $creances = Receivable::query()
            ->where(function ($q) use ($since) {
                $q->whereColumn('amount_paid', '<', 'amount');
                if ($since) {
                    $q->orWhere('updated_at', '>', $since);
                }
            })
            ->orderBy('due_date')
            ->get();

        $avances = CustomerAdvance::query()
            ->where('is_active', true)
            ->orderByDesc('advance_date')
            ->get();

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
        $relances = CustomerReminder::query()
            ->orderByDesc('reminder_date')
            ->get(['id', 'customer_id', 'receivable_id', 'channel', 'reminder_date', 'message']);

        // 🔴→✅ TICKET 14.77 — LES DEUX DERNIERS REFERENTIELS D'ELEVAGE.
        //
        // ⚠️ LE POSTE N'A PAS DE TABLE DES ESPECES : le libelle voyage AVEC le
        // type d'aliment, comme le code espece voyage avec la bande (F0.14).
        // Sans lui, la colonne « Espece Cible » de l'ecran Parametres Elevage
        // n'aurait qu'un UUID a afficher.
        $provendes = FeedType::with('species')
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
            });

        // 🔴→✅ TICKET 14.78 — LE DOMAINE ACHAT DESCEND AU POSTE.
        //
        // ⚠️⚠️ SANS LES FOURNISSEURS, LE POSTE NE PEUT RIEN ACHETER HORS LIGNE.
        // C'est la meme dependance que les clients pour la caisse (14.75) : un
        // achat sans fournisseur serait rejete a l'envoi, et l'operateur ne
        // comprendrait pas pourquoi.
        $fournisseurs = Supplier::query()
            ->where('is_active', true)
            ->orderBy('name')
            ->get(['id', 'name', 'category', 'phone', 'email', 'address']);

        // ⚠️ LE NOM DU FOURNISSEUR ET SA CATEGORIE VOYAGENT AVEC L'ACHAT. Le
        // poste doit pouvoir afficher la liste meme si le fournisseur a ete
        // archive depuis — et le referentiel, lui, ne sert que les actifs.
        //
        // ⚠️ LE STATUT SE CALCULE ICI, PAS AU POSTE : « Dette fournisseur » des
        // qu'une dette reste ouverte sur la piece, « Paye entierement » sinon.
        // Le poste ne recoit pas `payables` — deux regles de statut donneraient
        // deux listes differentes pour la meme ferme.
        $dettesParAchat = Payable::query()
            ->whereColumn('amount_paid', '<', 'amount')
            ->pluck('purchase_id')
            ->filter()
            ->flip();

        // Ticket U4 (D-U4) — un achat dont une LIGNE a changé depuis `since` redescend aussi : ses lignes
        // ne voyagent qu'avec lui (voir `$lignesAchat` plus bas).
        $achats = Purchase::with('supplier')
            ->when($since, fn ($q) => $q->where(fn ($w) => $this->pieceOuLigneModifiee($w, $since)))
            ->orderByDesc('purchase_date')
            ->get()
            ->map(fn (Purchase $achat) => [
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
            ]);

        // 🔴→✅ TICKET U4 (D-U4) — LES LIGNES DES ACHATS SERVIS DESCENDENT AVEC EUX.
        //
        // ⚠️⚠️ AU MÊME CURSEUR QUE LEUR PIÈCE, ET SEULEMENT POUR LES PIÈCES SERVIES : TOUTES les lignes de chaque
        // achat de `$achats` (un achat modifié, ou dont une ligne l'est, renvoie la liste COMPLÈTE de ses lignes —
        // le poste remplace alors celles qu'il tient, et une ligne retirée ici disparaît là-bas), JAMAIS une ligne
        // d'un achat non servi (le poste la refuserait : pièce inconnue). Sans elles, le PMP (`computePmp()`, Σ
        // qty × unit_price ÷ Σ qty sur TOUTES les lignes d'achat) et la marge du Top 5 étaient incalculables au
        // poste. `unit_price` est ici un VRAI prix unitaire (contrairement aux lignes de vente).
        $lignesAchat = $this->lignesDesPieces(
            \App\Models\PurchaseLine::class,
            'purchase_id',
            $achats->pluck('id'),
            fn ($ligne) => [
                'id' => $ligne->id,
                'purchase_id' => $ligne->purchase_id,
                'product_id' => $ligne->product_id,
                'product_name' => $ligne->product?->name,
                'qty' => (float) $ligne->qty,
                'unit_price' => (float) $ligne->unit_price,
            ],
        );

        // Ticket 15.20 (D8) : créance OUVERTE par fournisseur (part payée des achats retournés - remboursements déjà
        // encaissés). Servie CALCULÉE, sans filtre `since` (comme les dettes) : le poste en a besoin pour ne pas
        // proposer un remboursement que le serveur plafonnerait. Seuls les fournisseurs > 0 sont listés.
        $creancesFournisseurs = Supplier::query()
            ->whereIn('id', Purchase::whereNotNull('returned_at')->where('supplier_credit', '>', 0)->pluck('supplier_id'))
            ->get(['id', 'name'])
            ->map(fn (Supplier $f) => [
                'supplier_id' => $f->id,
                'supplier_name' => $f->name,
                'open_credit' => app(\App\Services\SupplierRefundService::class)->creanceOuverte($f->id),
            ])
            ->filter(fn (array $c) => $c['open_credit'] > 0)
            ->values();

        // ⚠️ LE MONTANT D'UN BON DE COMMANDE N'EST PAS STOCKE : il se somme sur
        // ses lignes. Le servir calcule evite que le poste le recompose a sa
        // facon — et que les deux surfaces affichent deux estimations.
        $bonsCommande = PurchaseOrder::with(['supplier', 'lines'])
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
            ]);

        // 🔴→✅ TICKET 14.84 — LES PARAMETRES GENERAUX DESCENDENT.
        //
        // ⚠️⚠️ AUCUN SECRET NE QUITTE LE SERVEUR. `company_settings` porte
        // `smtp_password_encrypted`, `twilio_auth_token_encrypted` et
        // `vonage_api_secret_encrypted` : un poste vole donnerait acces au
        // compte SMS et a la boite mail de la ferme. Seule l'IDENTITE de
        // l'entreprise et ses TAUX descendent — jamais un identifiant de
        // service, meme chiffre.
        $entreprise = CompanySetting::query()->first();
        $identite = $entreprise === null ? null : [
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

        // ⚠️⚠️ UN MODULE DESACTIVE DOIT DISPARAITRE DE L'ECRAN, PAS SEULEMENT
        // DE LA BASE. `modules_config` dit quelles especes la ferme exploite :
        // l'heliciculture est desactivee ici, et le poste continuait de
        // proposer la fiche Escargots. La maquette, elle, masque les blocs
        // `data-module="helico"`.
        $modules = ModuleConfig::query()
            ->orderBy('species_code')
            ->get(['id', 'species_code', 'is_enabled']);

        // ⚠️⚠️ `App\Models\Role`, JAMAIS `Spatie\Permission\Models\Role`.
        // Le modele de Spatie n'a pas `HasUuids` : il declare sa cle
        // auto-incrementee et Eloquent CASTE alors `roles.id` en entier. Un
        // UUID « 01a01168-... » devient « 1 » — les quatre roles descendaient
        // au poste avec le MEME identifiant, et la relation `permissions` ne
        // retrouvait plus aucune ligne du pivot. Le projet avait deja documente
        // ce piege sur le seeder (voir `App\Models\Role`) ; ce tirage l'a
        // repete. Le poste l'a signale au premier tirage reel : contrainte
        // d'unicite violee sur `roles_applicatifs.id`.
        $roles = Role::query()
            ->with('permissions:id,name')
            ->orderBy('name')
            ->get()
            ->map(fn ($role) => [
                'id' => (string) $role->id,
                'name' => $role->name,
                'permissions' => $role->permissions->pluck('name')->all(),
            ]);

        // ⚠️ NI MOT DE PASSE NI JETON : la liste sert a SAVOIR QUI travaille
        // sur la ferme, pas a s'authentifier.
        $utilisateurs = User::query()
            ->orderBy('name')
            ->get(['id', 'name', 'username', 'email', 'is_active'])
            ->map(fn (User $u) => [
                'id' => $u->id,
                'name' => $u->name,
                'username' => $u->username,
                'email' => $u->email,
                'is_active' => $u->is_active,
                'role' => $u->getRoleNames()->first(),
            ]);

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
        $notifications = Notification::query()
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
            ]);

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
        $revenusParBande = collect(app(LotRevenueService::class)->forLots())
            ->flatMap(fn (array $lignes, string $lotId) => collect($lignes)->map(fn (array $l) => [
                'lot_id' => $lotId,
                'product_id' => $l['product_id'],
                'label' => $l['label'],
                'amount' => $l['montant'],
            ]))
            ->values();

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
        $modelesAttestation = collect(AttestationService::TYPES)
            ->map(fn (string $type) => AttestationTemplate::forType($type))
            ->map(fn (AttestationTemplate $m) => [
                'id' => $m->id,
                'type' => $m->type,
                'body_text' => $m->body_text,
            ])
            ->values();
        $compteursAttestation = app(AttestationService::class)->compteurs();

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
        $sujets = Animal::query()
            ->with(['species:id,label', 'lot:id,code'])
            ->orderBy('identifier')
            ->get()
            ->map(fn (Animal $a) => [
                'id' => $a->id,
                'identifier' => $a->identifier,
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
            ]);

        // ⚠️ TICKET 15.15 — LES ESPÈCES D'ÉLEVAGE ACTIVES DESCENDENT.
        //
        // Le formulaire « Ajouter un Produit » propose la « Filière d'élevage »
        // (`products.species_id`) ; le poste n'avait aucune table des espèces. Seules
        // celles que la ferme exploite sont servies (`enabled()` : module actif) —
        // proposer une espèce éteinte laisserait créer un produit pour une filière
        // que l'exploitant a désactivée. Pas de filtre `since` : table de quelques
        // lignes, remplacée à chaque tirage.
        $especes = LivestockSpecies::query()
            ->enabled()
            ->orderBy('label')
            ->get(['id', 'code', 'label'])
            ->map(fn (LivestockSpecies $e) => [
                'id' => $e->id,
                'code' => $e->code,
                'label' => $e->label,
            ]);

        // ⚠️ BORNE A 100 LIGNES : la table grossit d'une ligne par action et
        // n'a d'interet, au poste, que pour les dernieres.
        // 🔴→✅ TICKET S3 — LE JOURNAL D'AUDIT (qui a fait quoi, depuis quelle adresse IP) est réservé aux comptes
        // qui gèrent les utilisateurs, comme son écran web. Les autres postes reçoivent une liste vide.
        $auditLogs = AuditLog::query()
            ->when(! $request->user()?->can('manage-users'), fn ($q) => $q->whereRaw('1 = 0'))
            ->with('user:id,name')
            ->orderByDesc('created_at')
            ->limit(100)
            ->get()
            ->map(fn (AuditLog $log) => [
                'id' => $log->id,
                'user_name' => $log->user?->name,
                'action' => $log->action,
                'module' => $log->module,
                'ip_address' => $log->ip_address,
                'created_at' => $log->created_at?->toIso8601String(),
            ]);

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
        $plan = ChartOfAccount::query()
            ->where('is_active', true)
            ->orderBy('code')
            ->get(['id', 'code', 'label', 'class']);

        $exercices = FiscalYear::query()
            ->orderByDesc('year')
            ->get(['id', 'year', 'start_date', 'end_date', 'status'])
            ->map(fn (FiscalYear $e) => [
                'id' => $e->id,
                'year' => $e->year,
                'start_date' => $e->start_date?->format('Y-m-d'),
                'end_date' => $e->end_date?->format('Y-m-d'),
                'status' => $e->status,
            ]);

        $ecritures = AccountingEntry::query()
            ->where('is_active', true)
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->orderByDesc('entry_date')
            ->get(['id', 'fiscal_year_id', 'entry_date', 'reference', 'source_type', 'is_locked', 'created_at'])
            ->map(fn (AccountingEntry $e) => [
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
            ]);

        // 🔴→✅ TICKET 15.28 — LE POSTE DOIT POUVOIR RETIRER UNE ECRITURE.
        //
        // ⚠️⚠️ Le tirage ci-dessus ne sert que les ecritures ACTIVES modifiees depuis `since` :
        // une ecriture ARCHIVEE (ou supprimee physiquement par une reinitialisation / une
        // restauration de sauvegarde) en SORT, et le poste, qui fusionne sans jamais rien
        // supprimer, la gardait pour toujours — comptee par son Journal, son Grand Livre et sa
        // Balance, sans aucune erreur. Contrat : `accounting_entry_ids` = identifiants de TOUTES
        // les ecritures actives, SANS filtre `since` (516 UUID, ~20 Ko). Le poste retire ce qui
        // n'y figure plus. Ne depend d'aucun tirage complet : un tirage incremental suffit.
        //
        // ⚠️ Le contrat sur les LIGNES : une ecriture servie arrive avec TOUTES ses lignes
        // courantes (`updateManual` supprime et recree les lignes, nouveaux ids) ; le poste
        // remplace les lignes de cette ecriture par celles-la.
        $idsEcrituresActives = AccountingEntry::query()
            ->where('is_active', true)
            ->orderBy('id')
            ->pluck('id')
            ->values();

        // ⚠️ LES LIGNES SUIVENT LEURS ECRITURES : servir les unes sans les
        // autres donnerait un journal desequilibre, ou des lignes orphelines
        // que le poste ne saurait rattacher.
        // ⚠️ TICKET 15.28-bis : PAR PAQUETS DE 5 000. Un `whereIn` de 33 000 identifiants dépasse la
        // limite de variables de la requête (SQLite ~32 766 ; MySQL 65 535 placeholders) : le tirage
        // entier échouait. Le résultat est identique (mêmes lignes, même contenu).
        $lignesEcriture = $ecritures->pluck('id')->chunk(5_000)->flatMap(
            fn ($paquet) => AccountingEntryLine::query()
                ->whereIn('entry_id', $paquet->values())
                ->get(['id', 'entry_id', 'account_id', 'cost_center_id', 'debit', 'credit'])
        )->values();

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
        $courriers = Correspondence::query()
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
            ]);

        // ⚠️ TICKET 15.25 — `administrative_documents` S'ECRIT AU POSTE
        // (`pushAdministrativeDocuments`), mêmes principes que `mails` et `archived_documents` :
        // tous les documents ACTIFS à chaque tirage, PLUS les RETIRÉS (`is_active = false`) dont
        // `updated_at > since`. `is_active` et `updated_at` (ISO 8601) sont servis. Dates en 'Y-m-d'.
        $documentsAdministratifs = AdministrativeDocument::query()
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
            ]);

        // ⚠️ TICKET 15.24 — `archived_documents` S'ECRIT AU POSTE (`pushArchivedDocuments`),
        // mêmes principes que `mails` : tous les documents ACTIFS à chaque tirage, PLUS les
        // RETIRÉS (`is_active = false`) dont `updated_at > since`. `is_active` et `updated_at`
        // (ISO 8601) sont servis. Le STATUT n'est PAS servi : il se déduit de `expiry_date`
        // (règle `ArchivedDocument::statutPour`, seuil 30 jours). Dates en 'Y-m-d'.
        $archives = ArchivedDocument::query()
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
            ]);

        // 🔴→✅ TICKET 14.81 — LE PERSONNEL ET SON POINTAGE DESCENDENT.
        //
        // ⚠️⚠️ LE POINTAGE EST L'ACTE DE TERRAIN PAR EXCELLENCE : il se fait a
        // 7 h a la ferme, ou le reseau n'est pas. Sans les employes au poste,
        // il n'y a personne a pointer ; sans les pointages deja saisis, le
        // chef d'equipe repointe quelqu'un que le web connait deja.
        $employes = Employee::query()
            ->where('is_active', true)
            ->orderBy('last_name')
            ->get(['id', 'first_name', 'last_name', 'position', 'base_salary', 'hire_date', 'status'])
            // 🔴→✅ TICKET S3 — LE SALAIRE NE DESCEND QU'AUX RÔLES RH. Il partait vers tout poste connecté,
            // caissier compris. Sans `view-rh`, le poste reçoit `null` et affiche « — » (salaire inconnu).
            ->each(function (Employee $employe) use ($request) {
                if (! $request->user()?->can('view-rh')) {
                    $employe->base_salary = null;
                }
            });

        // ⚠️ UN STAGIAIRE N'EST PAS UN EMPLOYE : la table est autonome, sans
        // relation vers `employees` — c'est aussi pourquoi la feuille de
        // pointage ne le couvre pas (ses absences vivent dans
        // `internship_absences`).
        $stagiaires = Internship::query()
            ->orderByDesc('start_date')
            ->get();

        // ⚠️ BORNE A 60 JOURS, ET C'EST DELIBERE. La table porte deja 870
        // lignes et grossit d'une par employe et par jour : la servir en
        // entier alourdirait chaque tirage pour une donnee que personne ne
        // consulte au-dela du mois courant. Le poste a besoin du mois en
        // cours pour ne pas repointer ; l'historique vit sur le web.
        $pointages = AttendanceRecord::query()
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
            ]);

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
        // Ticket U4 (D-U4) — une vente dont une LIGNE a changé depuis `since` redescend aussi (voir `$lignesVente`).
        $factures = Sale::with('customer')
            ->when($since, fn ($q) => $q->where(fn ($w) => $this->pieceOuLigneModifiee($w, $since)))
            ->orderByEffectiveDate()
            ->get()
            ->map(fn (Sale $vente) => [
                'id' => $vente->id,
                'customer_id' => $vente->customer_id,
                'customer_name' => $vente->customer?->name,
                'payment_mode' => $vente->payment_mode,
                'total' => $vente->total,
                'status' => $vente->status,
                'mecef_status' => $vente->mecef_status,
                'mecef_qr_ref' => $vente->mecef_qr_ref,
                'sold_at' => $vente->date_effective?->toIso8601String(),
            ]);

        // 🔴→✅ TICKET U4 (D-U4) — LES LIGNES DES VENTES SERVIES DESCENDENT AVEC ELLES.
        //
        // Même règle que `$lignesAchat` : toutes les lignes de chaque vente servie, aucune d'une vente non servie.
        // Sans elles, le Top 5 des produits et les « Ventes (mois) » porcines du Tableau de bord du poste ne
        // comptaient que les ventes saisies SUR CE POSTE, quand le web les compte toutes.
        // ⚠️ `manual_total_amount` EST LA SOURCE DE VÉRITÉ DU MONTANT de la ligne ; `unit_price` n'en est que
        // l'affichage dérivé (`manual_total_amount / qty`) : les deux sont servis tels que stockés.
        $lignesVente = $this->lignesDesPieces(
            \App\Models\SaleLine::class,
            'sale_id',
            $factures->pluck('id'),
            fn ($ligne) => [
                'id' => $ligne->id,
                'sale_id' => $ligne->sale_id,
                'product_id' => $ligne->product_id,
                'lot_id' => $ligne->lot_id,
                'qty' => (float) $ligne->qty,
                'unit_price' => (float) $ligne->unit_price,
                'manual_total_amount' => (float) $ligne->manual_total_amount,
            ],
        );

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
        $dettes = Payable::with('supplier')
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
            ]);

        // ⚠️ TABLE SINGLETON — une seule ligne, `current()` la cree au besoin.
        // Ces prefixes nomment les animaux sur le terrain (R1, T1, LOT-VOL-1) :
        // un poste qui les ignore proposerait sa propre convention, et deux
        // registres de la meme ferme ne se liraient plus ensemble.
        $numerotation = ElevageNumberingSetting::current()->only([
            'bande_format', 'lapine_prefix', 'male_prefix', 'truie_prefix',
            'verrat_prefix', 'portee_prefix', 'volaille_prefix', 'parc_prefix',
            'escargot_prefix',
        ]);

        $reproduction = $since
            ? LivestockReproductionEvent::query()
                ->where(fn ($q) => $q->where('status', 'en_cours')
                    ->orWhere('updated_at', '>', $since))
                ->orderByDesc('saillie_date')
                ->get()
            : LivestockReproductionEvent::query()
                ->orderByDesc('saillie_date')
                ->get();

        $reponse = [
            'server_time' => now()->toIso8601String(),
            // Ticket 15.50 — instant de la dernière réinitialisation des données (null : jamais). Un poste qui ne le
            // connaît pas purge ses données d'activité avant tout envoi.
            'data_reset_at' => $entreprise?->data_reset_at?->toIso8601String(),
            'products' => $products,
            'product_categories' => $categories,
            'livestock_lots' => $lots,
            'livestock_daily_entries' => $dailyEntries,
            'livestock_transfers' => $transferts,
            'feed_ration_standards' => $rations,
            'veterinary_withdrawal_periods' => $remanences,
            'prophylaxis_schedule_standards' => $prophylaxie,
            'veterinary_records' => $soins,
            'infirmary_records' => $infirmerie,
            'veterinary_calendar_events' => $calendrierVeterinaire,
            'livestock_reproduction_events' => $reproduction,
            'customers' => $clients,
            'receivables' => $creances,
            'customer_advances' => $avances,
            'customer_reminders' => $relances,
            'feed_types' => $provendes,
            'elevage_numbering' => $numerotation,
            'suppliers' => $fournisseurs,
            'purchases' => $achats,
            // Ticket U4 (D-U4) — lignes des achats servis ci-dessus, et d'eux seuls.
            'purchase_lines' => $lignesAchat,
            'supplier_credits' => $creancesFournisseurs,
            'purchase_orders' => $bonsCommande,
            'payables' => $dettes,
            'employees' => $employes,
            'internships' => $stagiaires,
            'attendance_records' => $pointages,
            'mails' => $courriers,
            'administrative_documents' => $documentsAdministratifs,
            'archived_documents' => $archives,
            'chart_of_accounts' => $plan,
            'fiscal_years' => $exercices,
            'accounting_entries' => $ecritures,
            'accounting_entry_lines' => $lignesEcriture,
            'accounting_entry_ids' => $idsEcrituresActives,
            'company_settings' => $identite,
            'modules_config' => $modules,
            'roles' => $roles,
            'users' => $utilisateurs,
            'audit_logs' => $auditLogs,
            'notifications' => $notifications,
            'lot_revenues' => $revenusParBande,
            'animals' => $sujets,
            'livestock_species' => $especes,
            'attestation_templates' => $modelesAttestation,
            'attestation_counts' => $compteursAttestation,
            'sales' => $factures,
            // Ticket U4 (D-U4) — lignes des ventes servies ci-dessus, et d'elles seules.
            'sale_lines' => $lignesVente,
            // ⚠️ TICKET 14.62 — CE QU'IL FAUT POUR SAISIR UNE DEPENSE HORS
            // LIGNE. Sans les comptes de tresorerie, le poste ne peut pas dire
            // QUI paie ; sans la liste des comptes de charge, il devrait la
            // recopier et les deux listes divergeraient au premier ajout.
            'treasury_accounts' => $comptesTresorerie,
            'expense_categories' => \App\Models\Expense::CATEGORIES,
        ];

        // Ticket H3 — chaque tirage est journalisé par poste (modale « Synchronisation » du web).
        app(JournalSynchronisationService::class)->tirage($request, $reponse);

        return response()->json($reponse);
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
    private function lignesDesPieces(string $modele, string $cle, Collection $ids, \Closure $enJson): Collection
    {
        return $ids->chunk(500)
            ->flatMap(fn ($paquet) => $modele::query()
                ->with('product:id,name')
                ->whereIn($cle, $paquet->values())
                ->orderBy('created_at')
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

        $result = [
            'cles_invalides' => $clesInvalides,
            'livestock_daily_entries' => ['accepted' => [], 'rejected' => []],
            'sales' => ['accepted' => [], 'rejected' => []],
            'stock_adjustments' => ['accepted' => [], 'rejected' => []],
            'veterinary_records' => ['accepted' => [], 'rejected' => []],
            'expenses' => ['accepted' => [], 'rejected' => []],
            'livestock_reproduction_events' => ['accepted' => [], 'rejected' => []],
            'infirmary_records' => ['accepted' => [], 'rejected' => []],
            'veterinary_calendar_events' => ['accepted' => [], 'rejected' => []],
            'purchases' => ['accepted' => [], 'rejected' => []],
            'attendance_records' => ['accepted' => [], 'rejected' => []],
            'products' => ['accepted' => [], 'rejected' => []],
            'suppliers' => ['accepted' => [], 'rejected' => []],
            'customers' => ['accepted' => [], 'rejected' => []],
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
            'modules_config',
            'roles',
            'users',
            'audit_logs',
            'notifications',
            'lot_revenues',
            'animals',
            'livestock_species',
            'attestation_templates',
            'attestation_counts',
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

        // ⚠️ LES FOURNISSEURS ET LES PRODUITS D'ABORD (15.15, 15.17) : un achat ou un
        // règlement du même envoi peut viser un fournisseur créé au poste à l'instant.
        if ($request->has('suppliers')) {
            $result['suppliers'] = $this->pushSuppliers($request->input('suppliers'), $request->user());
        }

        // ⚠️ LES CLIENTS AUSSI D'ABORD (15.18) : une vente ou un règlement du même envoi
        // peut viser un client créé au poste à l'instant.
        if ($request->has('customers')) {
            $result['customers'] = $this->pushCustomers($request->input('customers'), $request->user());
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
                $request->input('customer_advances'),
                $request->user(),
                $request->input('device_id'),
            );
        }

        // ⚠️ LES PRODUITS D'ABORD (15.15) : une vente, un achat ou un ajustement du même
        // envoi peut porter sur un produit créé au poste à l'instant. Traité après,
        // il serait refusé « produit inconnu » alors qu'il est dans le même paquet.
        if ($request->has('products')) {
            $result['products'] = $this->pushProducts($request->input('products'), $request->user());
        }

        if ($request->has('livestock_daily_entries')) {
            $result['livestock_daily_entries'] = $this->pushDailyEntries(
                $request->input('livestock_daily_entries'),
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
            $result['purchases'] = $this->pushPurchases($request->input('purchases'));
        }

        // ⚠️ APRÈS les achats : un règlement peut viser la dette que l'achat du même
        // envoi vient de créer.
        if ($request->has('supplier_payments')) {
            $result['supplier_payments'] = $this->pushSupplierPayments(
                $request->input('supplier_payments'),
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
                $request->input('supplier_refunds'),
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
                $request->input('sales'),
                $this->fichesAcceptees($result['livestock_daily_entries']['accepted'] ?? []),
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
                $request->input('stock_adjustments'),
                $this->identifiantsDeRetours($request->input('purchase_returns', [])),
            );
        }

        if ($request->has('veterinary_records')) {
            $result['veterinary_records'] = $this->pushVeterinaryRecords($request->input('veterinary_records'));
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
     * Ticket S1 — permission exigée pour écrire chaque table par le poste, identique à celle de l'écran web
     * correspondant (`$this->authorize()` des composants Livewire). Les autres tables écrivables contrôlent
     * déjà le rôle dans leur propre traitement.
     */
    private const PERMISSION_PAR_TABLE = [
        'livestock_daily_entries' => 'manage-elevage',
        'livestock_transfers' => 'manage-elevage',
        'livestock_reproduction_events' => 'manage-elevage',
        'infirmary_records' => 'manage-elevage',
        'veterinary_calendar_events' => 'manage-elevage',
        'veterinary_records' => 'manage-elevage',
        'expenses' => 'manage-achats',
        'purchases' => 'manage-achats',
        'attendance_records' => 'manage-rh',
        'sales' => 'manage-ventes',
        'stock_adjustments' => 'manage-stocks',
    ];

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
                    $issues[$rang] = ['ko' => ['id' => $validated['id'], 'reason' => MotifsRefusPush::ficheEleveurRequise()]];

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
                $issues[$rang] = ['ko' => [
                    'id' => $entry['id'] ?? null,
                    'reason' => "Une fiche existe deja pour cette bande a cette date, "
                        ."saisie depuis un autre poste. Comparez les deux avant de trancher.",
                ]];
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
        foreach ($issues as $issue) {
            if (isset($issue['ok'])) {
                $accepted[] = $issue['ok'];
            } else {
                $rejected[] = $issue['ko'];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
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
                    'entry_date' => ['required', 'date', 'before_or_equal:today'],
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
                $existant = LivestockReproductionEvent::find($validated['id']);
                if ($existant !== null) {
                    $etapes = validator($data, [
                        'palpation_date' => ['nullable', 'date', 'before_or_equal:today'],
                        'mise_bas_date_actual' => ['nullable', 'date', 'before_or_equal:today'],
                        'nes_vivants' => ['nullable', 'integer', 'min:0'],
                        'nes_morts' => ['nullable', 'integer', 'min:0'],
                        'status' => ['nullable', 'in:en_cours,echec,termine'],
                    ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                    // Seules les valeurs RENSEIGNEES s'appliquent : un poste qui ne connait pas une etape ne l'efface pas.
                    $maj = array_filter($etapes, fn ($v) => $v !== null);
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
                $evenement->save();

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
     */
    private function pushProducts(array $produits, $utilisateur): array
    {
        $accepted = [];
        $rejected = [];
        $service = app(ProductCatalogService::class);

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

                $existant = Product::find($id);

                $valides = validator(
                    $data,
                    $service->regles((string) ($data['pricing_mode'] ?? ''), $existant === null),
                    $service->messages() + MotifsRefusPush::messages(),
                    MotifsRefusPush::attributs(),
                )->validate();

                $existant === null
                    ? $service->creer($valides, $id)
                    : $service->modifier($existant, $valides, false);

                $accepted[] = $id;
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Fiches fournisseurs créées, modifiées ou archivées au poste (ticket 15.17).
     *
     * ⚠️⚠️ AVEC `products`, LE SEUL AUTRE RÉFÉRENTIEL OÙ LE POSTE ÉCRIT. Le serveur garde
     * la main : mêmes règles que la page web (`SupplierCatalogService`), droit
     * `manage-achats`, `id` du poste conservé. Un renvoi du même `id` est une
     * modification, jamais un doublon. Archiver = `is_active: false`.
     */
    private function pushSuppliers(array $fournisseurs, $utilisateur): array
    {
        $accepted = [];
        $rejected = [];
        $service = app(\App\Services\SupplierCatalogService::class);

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

                $valides = validator($data, $service->regles(), MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();
                $existant = \App\Models\Supplier::find($id);

                $existant === null
                    ? $service->creer($valides, $id)
                    : $service->modifier($existant, $valides);

                $accepted[] = $id;
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /**
     * Fiches clients créées, modifiées ou archivées au poste (ticket 15.18).
     *
     * Mêmes règles que la page « Liste des Clients » (`CustomerCatalogService`), droit
     * `manage-ventes`, `id` du poste conservé. Un renvoi du même `id` est une modification,
     * jamais un doublon. Archiver = `is_active: false`. Le plafond de crédit ne se lit pas
     * dans l'envoi : un poste ne relève pas le plafond d'un client.
     */
    private function pushCustomers(array $clients, $utilisateur): array
    {
        $accepted = [];
        $rejected = [];
        $service = app(\App\Services\CustomerCatalogService::class);

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

                $valides = validator($data, $service->regles(), MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();
                $existant = \App\Models\Customer::find($id);

                $existant === null
                    ? $service->creer($valides, $id)
                    : $service->modifier($existant, $valides);

                $accepted[] = $id;
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
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

    private function pushExpenses(array $expenses): array
    {
        $accepted = [];
        $rejected = [];

        foreach ($expenses as $data) {
            try {
                $validated = validator($data, [
                    'id' => ['required', 'uuid'],
                    'expense_date' => ['required', 'date'],
                    'label' => ['required', 'string', 'max:255'],
                    'category' => ['required', 'string', 'in:'.implode(',', \App\Models\Expense::CATEGORIES)],
                    'amount' => ['required', 'numeric', 'min:1'],
                    'treasury_account_id' => ['required', 'uuid', 'exists:treasury_accounts,id'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                // ⚠️ IDEMPOTENCE : deja recue, on acquitte sans rien rejouer.
                if (\App\Models\Expense::find($validated['id']) !== null) {
                    $accepted[] = $validated['id'];

                    continue;
                }

                DB::transaction(function () use ($validated) {
                    $depense = new \App\Models\Expense();
                    $depense->id = $validated['id'];
                    $depense->fill([
                        'expense_date' => $validated['expense_date'],
                        'label' => $validated['label'],
                        'category' => $validated['category'],
                        'amount' => $validated['amount'],
                        'treasury_account_id' => $validated['treasury_account_id'],
                        // Meme regle que l'ecran : une depense saisie est
                        // immediatement decaissee.
                        'status' => 'payee',
                        'is_active' => true,
                    ]);
                    $depense->save();

                    \App\Models\TreasuryAccount::where('id', $validated['treasury_account_id'])
                        ->decrement('balance', $validated['amount']);

                    app(\App\Actions\RecordExpenseAccountingEntryAction::class)
                        ->execute($depense->fresh());
                });

                $accepted[] = $validated['id'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $data['id'] ?? null, 'reason' => MotifsRefusPush::motif($e)];
            } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
                // ⚠️⚠️ UN REFUS COMPTABLE NE FAIT PAS ECHOUER TOUT L'ENVOI.
                // Aucun exercice ouvert, ou aucun qui couvre la date de la
                // depense : l'ecriture est impossible — mais
                // laisser remonter l'exception renverrait 500 pour la requete
                // ENTIERE : les fiches d'elevage et les ventes du meme envoi
                // seraient perdues avec elle, et le poste les rejouerait sans
                // jamais savoir pourquoi. La depense est rejetee AVEC SON
                // MOTIF, et elle seule.
                //
                // ⚠️ La transaction ayant ete annulee, le decaissement n'a pas
                // eu lieu : aucune caisse fausse ne subsiste.
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
     * Ticket 15.30 — (bande, jour) des fiches journalières ACCEPTÉES dans cet envoi.
     *
     * @param  array<int, string>  $idsAcceptes
     * @return array<string, true>  clés `lot_id|AAAA-MM-JJ`
     */
    private function fichesAcceptees(array $idsAcceptes): array
    {
        if ($idsAcceptes === []) {
            return [];
        }

        $cles = [];

        foreach (LivestockDailyEntry::whereIn('id', $idsAcceptes)->get(['lot_id', 'entry_date']) as $fiche) {
            $cles[$fiche->lot_id.'|'.$fiche->entry_date->format('Y-m-d')] = true;
        }

        return $cles;
    }

    /**
     * @param  array<string, true>  $fichesRecues  fiches acceptées dans le MÊME envoi (ticket 15.30)
     */
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

                DB::transaction(function () use ($validated, $saleData, $fichesRecues) {
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

                    // 🔴→✅ TICKET 14.80 — LA NORMALISATION FISCALE MANQUAIT.
                    //
                    // ⚠️⚠️ CE CANAL APPLIQUAIT LES QUATRE EFFETS ET OUBLIAIT LE
                    // CINQUIEME. La caisse WEB transmet chaque vente au
                    // dispositif MeCeF (`PosInterface::validateSale()`, ticket
                    // 7.1) ; l'envoi hors ligne, lui, ne le faisait pas. Une
                    // vente encaissee au comptoir sans reseau arrivait donc en
                    // base avec `mecef_status` NUL : jamais declaree a la DGI,
                    // sans QR, invisible de l'ecran Facturation. Le poste etant
                    // fait POUR travailler hors ligne, le trou fiscal grandit
                    // avec l'usage — et rien ne le signale.
                    //
                    // ⚠️ UN ECHEC DE TRANSMISSION NE PERD PAS LA VENTE : elle
                    // est marquee `erreur`, l'ecran Facturation la montre comme
                    // telle, et la retransmission depuis le web la rattrape.
                    // Lever l'exception ferait perdre les quatre autres effets
                    // deja appliques dans cette transaction.
                    try {
                        $mecef = app(\App\Services\Mecef\MecefGatewayInterface::class)
                            ->transmit($sale->fresh('lines'));

                        $sale->update([
                            'mecef_qr_ref' => $mecef['qr_ref'],
                            'mecef_status' => $mecef['success'] ? 'transmise' : 'erreur',
                        ]);
                    } catch (\Throwable $e) {
                        $sale->update(['mecef_status' => 'erreur']);
                        AuditLog::record('sale.mecef_failed_on_sync', 'facturation');
                    }

                });

                $accepted[] = $validated['id'];
            } catch (ValidationException $e) {
                // 'unique:sales,id' échoue si cette vente a déjà été
                // synchronisée précédemment — traité comme un succès
                // silencieux (déjà là), jamais une erreur, pour permettre
                // un push répété sans risque en cas de coupure réseau.
                if (isset($saleData['id']) && Sale::where('id', $saleData['id'])->exists()) {
                    $accepted[] = $saleData['id'];
                } else {
                    $rejected[] = ['id' => $saleData['id'] ?? null, 'reason' => MotifsRefusPush::motif($e)];
                }
            } catch (SaleDateRefusedException $e) {
                // 🔴→✅ TICKET 15.30 — date refusée par `VerifySaleDateAction` : rejet MOTIVÉ de cette
                // vente seule. Le poste la passe en `conflict` avec ce motif, au lieu de la rejouer.
                $rejected[] = ['id' => $saleData['id'] ?? null, 'reason' => $e->getMessage()];
            } catch (NoOpenFiscalYearException|ClosedFiscalYearException $e) {
                // 🔴→✅ TICKET 15.30 — ANCIEN DÉFAUT : seule `ValidationException` était rattrapée ; un
                // exercice absent ou clos levé par `AccountingEntryService::record` (via
                // `RecordSaleAccountingEntryAction`) partait en 500 pour l'envoi ENTIER, que le poste
                // rejouait en boucle, emportant fiches et autres ventes. Même règle que les achats,
                // avances et retours. La transaction ayant été annulée, ni stock, ni fiche, ni caisse
                // n'ont bougé.
                $rejected[] = ['id' => $saleData['id'] ?? null, 'reason' => 'Vente refusée : '.$e->getMessage()];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
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
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                if (VeterinaryRecord::where('id', $validated['id'])->exists()) {
                    $accepted[] = $validated['id'];

                    continue;
                }

                // Ticket S1 — seuls les champs validés partent : ni `is_active` ni `daily_entry_id` venus du poste.
                app(RecordVeterinaryCareAction::class)->execute(
                    Arr::except($validated, 'withdrawal_days'),
                    (int) ($soin['withdrawal_days'] ?? 0),
                );

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
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                $clientRef = $validated['client_ref'] ?? null;

                // 🔴→✅ TICKET 15.20 — UN RETOUR FOURNISSEUR NE SE DÉCRÉMENTE PAS DEUX FOIS. Le serveur décrémente
                // lui-même le stock d'un retour (`PurchaseReturnService`, `purchase_returns`) ; un poste qui joindrait
                // en plus sa propre sortie « retour fournisseur » ferait descendre le stock deux fois, sans erreur.
                // Une sortie désignée comme retour (type de référence, ou référence = id d'un retour / d'un achat
                // retourné, du paquet ou déjà reçu) est donc REFUSÉE avec son motif. Une sortie sans rapport avec un
                // retour (perte d'inventaire) s'applique normalement.
                if ($validated['type'] === 'sortie' && $this->sortieDeRetourFournisseur($validated, $clientRef, $identifiantsDeRetours)) {
                    $rejected[] = [
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

                app(AdjustStockAction::class)->execute(
                    product: $product,
                    delta: $delta,
                    referenceType: $validated['reference_type'],
                    // ⚠️ C'est cette trace qui rend le renvoi inoffensif.
                    referenceId: $clientRef,
                    reason: $validated['reason'] ?? null,
                );

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
                app(RecordStockAdjustmentEntryAction::class)
                    ->execute($product->fresh(), $delta, $validated['reason'] ?? null);

                // ⚠️ ON ACQUITTE L'IDENTIFIANT DE LA LIGNE DU POSTE. Le repli
                // sur `product_id` etait le defaut : deux ajustements sur le
                // meme produit auraient d'ailleurs porte le meme accuse.
                $accepted[] = $clientRef ?? $validated['product_id'];
            } catch (ValidationException $e) {
                $rejected[] = ['client_ref' => $adj['client_ref'] ?? null, 'reason' => MotifsRefusPush::motif($e)];
            } catch (\Throwable $e) {
                // Ticket U5 : un motif technique du framework (anglais) devient une phrase française.
                $rejected[] = ['client_ref' => $adj['client_ref'] ?? null, 'reason' => MessagesErreurFr::pourUtilisateur($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }
}
