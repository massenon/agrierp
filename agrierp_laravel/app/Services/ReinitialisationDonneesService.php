<?php

namespace App\Services;

use App\Models\AuditLog;
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
            'sale_lines', 'sales', 'credit_notes', 'quotes', 'receivables',
            'advance_imputations', 'customer_advances', 'customer_reminders', 'customers',
            // Achats et fournisseurs
            'purchase_lines', 'purchases', 'purchase_order_lines',
            'purchase_orders', 'purchase_returns', 'payables',
            // Ticket 15.20 : règlements (15.16) et remboursements fournisseurs - `supplier_payments` avait été oublié.
            'supplier_payments', 'supplier_refunds', 'suppliers',
            'expenses',
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
            // 🔴 Ticket 15.50 : les immobilisations PRÉSERVÉES alors que leurs écritures d'acquisition et
            // d'amortissement étaient effacées — un registre sans aucune écriture pour le justifier.
            'fixed_assets',
            // Administration — 🔴 Ticket 15.50 : la liste nommait `correspondences`, table qui n'existe pas :
            // les courriers s'appellent `mails`, et n'étaient JAMAIS vidés.
            'administrative_documents', 'archived_documents', 'mails',
            // 🔴 Ticket 15.50 : les notifications PRÉSERVÉES pointaient vers des bandes, produits et soins
            // effacés (« Stock sous le seuil », « Mortalité anormale » d'une bande qui n'existe plus).
            'notifications',
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
            // Ticket 15.50 : référentiels jamais classés (normes de croissance, modèles d'attestation, préfixes
            // de numérotation de l'élevage).
            'growth_standards', 'attestation_templates', 'elevage_numbering_settings',
            'audit_logs',
        ];
    }

    /**
     * Ticket 15.50 — tables TECHNIQUES du cadriciel, ni vidées ni « préservées » au sens métier. ⚠️ Les jetons et
     * sessions restent : les vider déconnecterait l'administrateur qui vient de lancer l'opération.
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
     * @return array<string, int>  nombre de lignes supprimées, par table
     */
    public function executer(): array
    {
        $supprimees = [];

        // ⚠️ CONTRAINTES SUSPENDUES LE TEMPS DE L'OPÉRATION : vider dans un
        // ordre « correct » est impossible à garantir sur un schéma qui évolue,
        // et un échec à mi-parcours laisserait la base à moitié vidée.
        Schema::withoutForeignKeyConstraints(function () use (&$supprimees) {
            DB::transaction(function () use (&$supprimees) {
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
    private function remettreLesSoldesAZero(): void
    {
        if (Schema::hasTable('products')) {
            DB::table('products')->update(['stock_qty' => 0]);
        }

        if (Schema::hasTable('treasury_accounts')) {
            DB::table('treasury_accounts')->update(['balance' => 0]);
        }
    }
}
