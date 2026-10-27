<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\CompanySetting;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.56 (Sprint 14) — RÉINITIALISATION DES DONNÉES DE TEST.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  ⚠️⚠️ LA VÉRITÉ QU'IL FAUT DIRE PLUTÔT QUE MASQUER
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * L'application **ne sait PAS distinguer** une vente de démonstration d'une
 * vente réelle : les deux vivent dans la même table, avec la même forme. Aucune
 * colonne ne les sépare, et en ajouter une aujourd'hui ne rétro-marquerait pas
 * l'existant.
 *
 * Cette opération vide donc **TOUTES les données transactionnelles**, pas
 * seulement celles produites par le jeu de démonstration. Le présenter comme un
 * « nettoyage des données de test » serait un mensonge dangereux — l'écran le
 * dit en toutes lettres, et c'est ce qui justifie les trois verrous
 * (bascule désactivée par défaut, mot de confirmation à saisir, journalisation).
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  CE QUI EST PRÉSERVÉ, ET POURQUOI
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Le partage suit exactement celui des seeders : `DatabaseSeeder` pose les
 * paramètres de base, `DemoDataSeeder` les données d'activité.
 *
 * ⚠️ **LES COMPTES ET LES RÔLES SURVIVENT.** Vider les utilisateurs
 * verrouillerait l'application hors de portée de tout le monde, y compris de
 * l'administrateur qui vient de lancer l'opération.
 *
 * ⚠️ **LE JOURNAL D'AUDIT SURVIT.** C'est la trace de ce qui s'est passé — y
 * compris de cette réinitialisation. L'effacer supprimerait la preuve de
 * l'effacement.
 *
 * ⚠️ **LES RÉFÉRENTIELS SURVIVENT** : plan comptable, exercices, comptes de
 * trésorerie, catalogue produits, espèces, rations, protocoles, centres de
 * coût, barème ITS, réglages d'entreprise. Ce sont les « paramètres de base »
 * que le client demande explicitement de conserver.
 */
class ReinitialisationDonneesService
{
    /**
     * Ticket R-1 — LES VERROUS ET LES MESSAGES VIVENT ICI, UNE SEULE FOIS. L'écran web
     * (`Livewire\Parametres\ReinitialisationDonnees`) et la route du poste
     * (`Api\ReinitialisationDonneesController`) les lisent tous deux : un mot de confirmation ou un message
     * changé d'un côté seulement ferait diverger les deux surfaces sans bruit.
     */
    public const MOT_DE_CONFIRMATION = 'REINITIALISER';

    /** Refus quand la bascule est fausse (verrou 1). */
    public const REFUS_MODE_DEMO = 'Réinitialisation refusée : le mode démonstration n\'est pas activé.';

    /** Message sous le champ quand le mot n'est pas recopié (verrou 2). */
    public static function messageConfirmation(): string
    {
        return 'Saisissez '.self::MOT_DE_CONFIRMATION.' pour confirmer.';
    }

    /**
     * Le nombre réel est annoncé : « données réinitialisées » sans chiffre laisserait l'administrateur sans
     * moyen de vérifier ce qui s'est passé.
     */
    public static function messageResultat(int $total): string
    {
        return $total > 0
            ? "Réinitialisation effectuée — {$total} enregistrement(s) supprimé(s)."
            : 'Aucune donnée d\'activité à supprimer.';
    }

    public static function messageBascule(bool $actif): string
    {
        return $actif
            ? 'Mode démonstration activé — l\'onglet de réinitialisation est accessible.'
            : 'Mode démonstration désactivé.';
    }

    public static function modeDemoActif(): bool
    {
        return (bool) (CompanySetting::first()?->demo_mode_enabled ?? false);
    }

    /**
     * Active ou désactive le mode démonstration ; rend le nouvel état, `null` sans réglages d'entreprise.
     *
     * ⚠️ LA BASCULE ELLE-MÊME EST JOURNALISÉE : ouvrir l'accès à une opération destructrice est un acte
     * administratif qui doit laisser une trace, au même titre que l'effacement.
     */
    public static function basculerModeDemo(): ?bool
    {
        $reglages = CompanySetting::first();

        if ($reglages === null) {
            return null;
        }

        $actif = ! $reglages->demo_mode_enabled;
        $reglages->update(['demo_mode_enabled' => $actif]);

        AuditLog::record($actif ? 'demo_mode.enabled' : 'demo_mode.disabled', 'parametres');

        return $actif;
    }

    /**
     * Tables d'activité vidées, dans un ordre sans importance : les contraintes
     * de clés étrangères sont suspendues le temps de l'opération.
     *
     * ⚠️ LISTE EXPLICITE, jamais un balayage du schéma. Un balayage
     * embarquerait la première table de configuration ajoutée plus tard, et
     * l'exploitation perdrait ses réglages sans que personne ne l'ait décidé.
     *
     * @return array<int, string>
     */
    public static function tablesTransactionnelles(): array
    {
        return [
            // Ventes et clientèle
            // Ticket VC-1 : encaissements de créances reçus des postes (idempotence) — AVANT les créances et les clients
            // qu'ils référencent (clés étrangères).
            'receivable_payments',
            'sale_lines', 'sales', 'credit_notes', 'quotes', 'receivables',
            'advance_imputations', 'customer_advances', 'customer_reminders', 'customers',
            // Achats et fournisseurs
            'purchase_lines', 'purchases', 'purchase_order_lines',
            'purchase_orders', 'purchase_returns', 'payables',
            // Ticket 15.20 : règlements (15.16) et remboursements fournisseurs - `supplier_payments` avait été oublié.
            'supplier_payments', 'supplier_refunds', 'suppliers',
            // Ticket DEP1 — les lignes d'abord (enfants de `expenses`).
            'expense_lines', 'expenses',
            // Stock
            'stock_movements',
            // Élevage
            'livestock_daily_entries', 'livestock_reproduction_events',
            'veterinary_records', 'veterinary_withdrawal_periods',
            'veterinary_calendar_events', 'infirmary_records',
            // Ticket 15.50 : transferts entre bandes (15.46), oubliés.
            'livestock_transfers',
            'transformations', 'animals', 'livestock_lots',
            // Ressources humaines
            'payslips', 'attendance_records', 'internship_absences',
            'internships', 'employees',
            // Comptabilité
            'accounting_entry_lines', 'accounting_entries', 'accounting_reference_sequences', 'periodic_closures',
            'bank_statement_lines',
            // Administration — 🔴 Ticket 15.50 : la liste nommait `correspondences`, table qui n'existe pas :
            // les courriers s'appellent `mails`, et n'étaient JAMAIS vidés.
            'administrative_documents', 'archived_documents', 'mails',
            // 🔴 Ticket 15.50 : les notifications PRÉSERVÉES pointaient vers des bandes, produits et soins
            // effacés (« Stock sous le seuil », « Mortalité anormale » d'une bande qui n'existe plus).
            'notifications',
            // Ticket H3 — journal des tirages et envois des postes : après une réinitialisation, chaque poste purge
            // ses données et repart de zéro ; ses compteurs d'avant ne décrivent plus rien.
            'journal_synchronisation',
            // Ticket S-T6 — demandes de synchronisation aux postes et contrôles de cohérence : même raison.
            'demandes_synchronisation_servies', 'demandes_synchronisation', 'controles_coherence',
            // Ticket S-T5 — correspondances d'identifiants des postes : après une réinitialisation, les postes purgent
            // leurs données ; les identifiants qu'elles traduisaient ne seront plus jamais envoyés.
            'correspondances_identifiants',
            // Ticket SW-1 — curseurs et drapeaux de resynchronisation des postes : après une réinitialisation, chaque
            // poste purge ses données et repart de zéro ; son curseur d'avant ne décrit plus rien.
            'poste_synchronisations',
        ];
    }

    /**
     * Tables explicitement PRÉSERVÉES — documentées pour que la décision soit
     * lisible sans avoir à déduire par soustraction.
     *
     * @return array<int, string>
     */
    public static function tablesPreservees(): array
    {
        return [
            'users', 'roles', 'permissions', 'model_has_roles', 'model_has_permissions',
            // Ticket 15.50 : `module_configs` n'existait pas — la table est `modules_config`.
            'role_has_permissions', 'company_settings', 'modules_config',
            'chart_of_accounts', 'fiscal_years', 'treasury_accounts',
            'products', 'product_categories', 'livestock_species',
            'feed_types', 'feed_ration_standards', 'prophylaxis_schedule_standards',
            'cost_centers', 'income_tax_brackets',
            // Immobilisations semées en reprise d'antériorité (`FixedAssetsSeeder`) : paramètres de base. Celles
            // ACHETÉES dans l'application sont retirées par `remettreLesImmobilisations()` (ticket 15.50).
            'fixed_assets',
            // Ticket 15.50 : référentiels jamais classés (normes de croissance, modèles d'attestation, préfixes
            // de numérotation de l'élevage).
            'growth_standards', 'attestation_templates', 'elevage_numbering_settings',
            'audit_logs',
            // Ticket ARC1 — journal de la Corbeille (qui a restauré ou supprimé définitivement quoi) : une trace d'administration
            // comme `audit_logs`, utile précisément après une suppression irréversible. Ses éléments, eux, sont partis.
            'corbeille_operations',
            // ATT-3 — numéros d'attestation FIGÉS (un par émission du poste ou du web) : le rang d'un numéro se compte sur
            // `audit_logs`, préservé ; vider ceci laisserait un poste rejouer une émission et recevoir un AUTRE numéro.
            'attestation_emissions',
        ];
    }

    /**
     * Ticket 15.50 — tables TECHNIQUES du cadriciel, ni vidées ni « préservées » au sens métier. Sessions et jetons
     * sont vidés à part (ticket 15.54, `ViderSessionsService`), en gardant la session de l'administrateur.
     *
     * @return array<int, string>
     */
    public static function tablesTechniques(): array
    {
        return [
            'migrations', 'cache', 'cache_locks', 'jobs', 'job_batches', 'failed_jobs',
            'sessions', 'password_reset_tokens', 'personal_access_tokens',
        ];
    }

    /**
     * Vide les données d'activité et remet les soldes dérivés à zéro.
     *
     * Ticket R-1 — [$jetonAConserver] : jeton Sanctum du POSTE qui a lancé l'opération, gardé comme la
     * session web de l'administrateur (même raison : il doit purger et tirer aussitôt, sans se reconnecter).
     *
     * @return array<string, int>  nombre de lignes supprimées, par table
     */
    public function executer(int|string|null $jetonAConserver = null): array
    {
        $supprimees = [];

        // ⚠️ CONTRAINTES SUSPENDUES LE TEMPS DE L'OPÉRATION : vider dans un
        // ordre « correct » est impossible à garantir sur un schéma qui évolue,
        // et un échec à mi-parcours laisserait la base à moitié vidée.
        Schema::withoutForeignKeyConstraints(function () use (&$supprimees) {
            DB::transaction(function () use (&$supprimees) {
                // ⚠️ AVANT le vidage : il faut encore lire le type des écritures d'acquisition.
                $immobilisationsAchetees = $this->remettreLesImmobilisations();
                if ($immobilisationsAchetees > 0) {
                    $supprimees['fixed_assets'] = $immobilisationsAchetees;
                }

                foreach (static::tablesTransactionnelles() as $table) {
                    if (! Schema::hasTable($table)) {
                        continue;
                    }

                    $supprimees[$table] = DB::table($table)->count();
                    DB::table($table)->delete();
                }

                $this->remettreLesSoldesAZero();

                // Ticket 15.50 — la marque que les postes lisent au tirage (voir la migration).
                if (Schema::hasColumn('company_settings', 'data_reset_at')) {
                    DB::table('company_settings')->update(['data_reset_at' => now()]);
                }
            });
        });

        // 🔁 Ticket 15.54 — sessions vidées et jetons des postes révoqués : chaque poste se reconnecte, et son
        // premier tirage applique la réinitialisation. La session de l'administrateur qui l'a lancée est conservée.
        app(ViderSessionsService::class)->vider(
            app()->runningInConsole() ? null : session()->getId(),
            $jetonAConserver,
        );

        AuditLog::record('donnees.reinitialisees', 'parametres');

        return array_filter($supprimees);
    }

    /**
     * Remet à zéro les soldes DÉRIVÉS des transactions effacées.
     *
     * ⚠️ SANS CETTE ÉTAPE, L'ÉTAT SERAIT PIRE QU'AVANT. `products.stock_qty` et
     * `treasury_accounts.balance` sont mutés au fil des mouvements : les laisser
     * à leur valeur de démonstration après avoir effacé les mouvements qui les
     * ont produits donnerait un stock et une caisse **sans aucune écriture pour
     * les justifier** — précisément l'incohérence que ce projet traque depuis
     * le début, et qu'aucun rapport ne pourrait plus expliquer.
     */
    /**
     * 🔴 Ticket 15.50 — LES IMMOBILISATIONS SUIVENT LEURS ÉCRITURES.
     *
     * Le registre était conservé tel quel alors que les écritures d'acquisition, d'apport et d'amortissement
     * étaient effacées : des biens « capitalisés » sans aucune écriture, et des achats de démonstration
     * restés à l'actif.
     *  - un bien ACHETÉ dans l'application (écriture `asset_acquisition`) est une opération : il est supprimé ;
     *  - un bien ENTRÉ PAR APPORT (`asset_opening`) ou jamais capitalisé revient à l'état de sa reprise
     *    d'antériorité : hors comptabilité, en service (sa cession ou sa réforme était une opération).
     *
     * @return int nombre de biens achetés supprimés
     */
    private function remettreLesImmobilisations(): int
    {
        if (! Schema::hasTable('fixed_assets')) {
            return 0;
        }

        $achetes = DB::table('fixed_assets')
            ->whereIn('acquisition_entry_id', DB::table('accounting_entries')
                ->where('source_type', 'asset_acquisition')->select('id'))
            ->pluck('id');

        DB::table('fixed_assets')->whereIn('id', $achetes)->delete();

        DB::table('fixed_assets')->update([
            'is_capitalized' => false, 'acquisition_entry_id' => null,
            'status' => 'en_service', 'disposal_date' => null, 'disposal_reason' => null,
        ]);

        return $achetes->count();
    }

    private function remettreLesSoldesAZero(): void
    {
        if (Schema::hasTable('products')) {
            DB::table('products')->update(['stock_qty' => 0]);
        }

        if (Schema::hasTable('treasury_accounts')) {
            DB::table('treasury_accounts')->update(['balance' => 0]);
        }

        // 🔁 Ticket 15.53 — un exercice clôturé dont toutes les écritures (report à nouveau compris) viennent d'être
        // effacées n'a plus rien à protéger : il est rouvert, sinon aucune saisie ne pourrait plus y être datée.
        if (Schema::hasTable('fiscal_years')) {
            DB::table('fiscal_years')->where('status', 'cloture')
                ->update(['status' => 'ouvert', 'closed_at' => null, 'closed_by' => null, 'updated_at' => now()]);
        }
    }
}
