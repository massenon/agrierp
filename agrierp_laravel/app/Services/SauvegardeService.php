<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;

/**
 * Ticket 14.57 (Sprint 14) — SAUVEGARDES DE LA BASE.
 *
 * La commande `agrierp:backup` (ticket 11.1) existait déjà : `mysqldump` réel,
 * rétention 30 jours, planifiée. Ce service ne la remplace pas — il l'entoure
 * de ce qui manquait : une **portée** (base complète ou module), un listing
 * exploitable, et une résolution de chemin sûre.
 *
 * ⚠️ **DEUX MOTEURS, ET C'EST ASSUMÉ.** `mysqldump` reste le bon outil pour une
 * sauvegarde COMPLÈTE : il capture le schéma, les index et les contraintes,
 * qu'aucun export applicatif ne reproduit fidèlement. Mais il est absent de
 * beaucoup d'hébergements, et ne sait pas exporter « le module Élevage ». Le
 * moteur portable prend donc le relais pour les exports par module et lorsque
 * `mysqldump` fait défaut — en le DISANT, jamais en laissant croire à une
 * sauvegarde complète.
 *
 * ⚠️ **LA PORTÉE EST INSCRITE DANS LE NOM DU FICHIER.** Sans elle, la colonne
 * « Table » de l'écran devrait deviner, et un export partiel serait
 * indiscernable d'une sauvegarde complète au moment de la restauration — le
 * pire moment pour se tromper.
 */
class SauvegardeService
{
    public const DOSSIER = 'backups';

    /**
     * Modules exportables séparément, et les tables de chacun.
     *
     * ⚠️ LISTE EXPLICITE : un découpage automatique par préfixe de table
     * rangerait mal la première table dont le nom ne suit pas la convention, et
     * l'export « Élevage » perdrait des données sans que personne ne le voie.
     *
     * ⚠️ L'ORDRE COMPTE : ENFANTS D'ABORD, PARENTS ENSUITE. Les tables sont
     * vidées dans CET ordre à l'import. Suspendre les clés étrangères ne suffit
     * pas — SQLite ignore le pragma à l'intérieur d'une transaction, et un
     * ordre incorrect n'échoue alors que sur certains moteurs. Un code correct
     * sans suspension vaut mieux qu'un code qui dépend d'elle.
     *
     * @return array<string, array{libelle: string, tables: array<int, string>}>
     */
    public static function modules(): array
    {
        return [
            'ventes' => ['libelle' => 'Ventes & Clients', 'tables' => [
                'sale_lines', 'credit_notes', 'quotes', 'advance_imputations', 'receivables',
                'customer_advances', 'customer_reminders', 'sales', 'customers',
            ]],
            'achats' => ['libelle' => 'Achats & Fournisseurs', 'tables' => [
                'purchase_lines', 'purchase_order_lines', 'purchase_returns',
                // Ticket 15.20 : enfants de `suppliers` (et de `treasury_accounts`), donc AVANT `suppliers`.
                // `supplier_payments` (15.16) avait été oublié : un remplacement du module le laissait orphelin.
                'supplier_payments', 'supplier_refunds',
                'payables', 'purchases', 'purchase_orders', 'expenses',
                'suppliers',
            ]],
            'stocks' => ['libelle' => 'Stocks', 'tables' => [
                'stock_movements', 'products', 'product_categories',
            ]],
            'elevage' => ['libelle' => 'Élevage', 'tables' => [
                'livestock_daily_entries', 'livestock_reproduction_events',
                'animals', 'transformations', 'veterinary_records',
                'veterinary_withdrawal_periods', 'veterinary_calendar_events',
                'infirmary_records', 'livestock_lots', 'feed_ration_standards',
                'prophylaxis_schedule_standards', 'feed_types', 'livestock_species',
            ]],
            'comptabilite' => ['libelle' => 'Comptabilité', 'tables' => [
                // Ticket 15.20b : le compteur de numéros voyage AVEC les écritures (exporté, vidé, restauré).
                // Avant : absent, il survivait au remplacement — orphelin, et sa clé étrangère vers `fiscal_years`
                // faisait même échouer le vidage. Enfant de `fiscal_years` : donc listé AVANT elle.
                'accounting_entry_lines', 'accounting_entries', 'accounting_reference_sequences', 'periodic_closures',
                'bank_statement_lines', 'fixed_assets', 'cost_centers',
                'treasury_accounts', 'fiscal_years', 'chart_of_accounts',
            ]],
            'rh' => ['libelle' => 'Ressources Humaines', 'tables' => [
                'payslips', 'attendance_records', 'internship_absences',
                'internships', 'employees', 'income_tax_brackets',
            ]],
        ];
    }

    /**
     * Sauvegarde complète.
     *
     * ⚠️ `mysqldump` D'ABORD, REPLI PORTABLE ENSUITE — et le nom du fichier dit
     * lequel a servi. Un export applicatif ne contient pas le schéma : le
     * présenter comme équivalent laisserait croire à une restauration possible
     * sur une base vierge.
     *
     * @return array{fichier: string, moteur: string}
     */
    public function genererComplete(): array
    {
        Storage::disk('local')->makeDirectory(self::DOSSIER);

        if ($this->mysqldumpDisponible()) {
            $fichier = 'backup_'.now()->format('Y-m-d_Hi').'_complete.sql';

            if ($this->executerMysqldump(Storage::disk('local')->path(self::DOSSIER.'/'.$fichier))) {
                return ['fichier' => $fichier, 'moteur' => 'mysqldump'];
            }
        }

        // Repli : données seules, sans schéma. Le suffixe le dit.
        $fichier = 'backup_'.now()->format('Y-m-d_Hi').'_donnees.sql';
        $this->ecrire($fichier, $this->toutesLesTables());

        return ['fichier' => $fichier, 'moteur' => 'donnees'];
    }

    /** Sauvegarde d'un seul module. */
    public function genererModule(string $module): ?string
    {
        $definition = static::modules()[$module] ?? null;

        if ($definition === null) {
            return null;
        }

        Storage::disk('local')->makeDirectory(self::DOSSIER);

        $fichier = 'backup_'.now()->format('Y-m-d_Hi').'_'.$module.'.sql';
        $this->ecrire($fichier, $definition['tables']);

        return $fichier;
    }

    /**
     * Sauvegardes présentes, la plus récente d'abord.
     *
     * @return array<int, array{fichier: string, date: \Illuminate\Support\Carbon, portee: string, taille: int}>
     */
    public function lister(): array
    {
        Storage::disk('local')->makeDirectory(self::DOSSIER);

        $fichiers = collect(Storage::disk('local')->files(self::DOSSIER))
            ->filter(fn ($chemin) => str_ends_with($chemin, '.sql'))
            ->map(function ($chemin) {
                $nom = basename($chemin);

                return [
                    'fichier' => $nom,
                    'date' => \Illuminate\Support\Carbon::createFromTimestamp(
                        Storage::disk('local')->lastModified($chemin)
                    ),
                    'portee' => $this->porteeDe($nom),
                    'taille' => Storage::disk('local')->size($chemin),
                ];
            })
            ->sortByDesc(fn ($f) => $f['date']->timestamp)
            ->values()
            ->all();

        return $fichiers;
    }

    /**
     * Chemin absolu d'une sauvegarde, ou `null`.
     *
     * ⚠️⚠️ **LE NOM EST VÉRIFIÉ CONTRE LA LISTE RÉELLE, jamais concaténé.**
     * Un nom fourni par la requête et collé au dossier permettrait de remonter
     * l'arborescence (`../../.env`) et de télécharger n'importe quel fichier du
     * serveur — identifiants de base compris. Le fichier doit exister DANS le
     * dossier des sauvegardes pour être servi.
     */
    public function chemin(string $fichier): ?string
    {
        $connu = collect($this->lister())->contains(fn ($f) => $f['fichier'] === $fichier);

        if (! $connu) {
            return null;
        }

        return Storage::disk('local')->path(self::DOSSIER.'/'.$fichier);
    }

    /** Portée lisible, déduite du suffixe du nom de fichier. */
    private function porteeDe(string $nom): string
    {
        foreach (static::modules() as $cle => $definition) {
            if (str_ends_with($nom, '_'.$cle.'.sql')) {
                return $definition['libelle'];
            }
        }

        if (str_ends_with($nom, '_donnees.sql')) {
            // ⚠️ Dit explicitement ce qui manque : sans schéma, ce fichier ne
            // restaure rien sur une base vierge.
            return 'Toutes les données (sans schéma)';
        }

        // Les fichiers du ticket 11.1 n'ont aucun suffixe : ce sont des
        // sauvegardes complètes, et il ne faut pas les afficher comme inconnues.
        return 'Base complète';
    }

    private function mysqldumpDisponible(): bool
    {
        if (config('database.default') !== 'mysql') {
            return false;
        }

        exec('mysqldump --version 2>&1', $sortie, $code);

        return $code === 0;
    }

    private function executerMysqldump(string $chemin): bool
    {
        $config = config('database.connections.mysql');

        $commande = sprintf(
            'mysqldump --host=%s --port=%s --user=%s --password=%s %s > %s 2>&1',
            escapeshellarg($config['host'] ?? '127.0.0.1'),
            escapeshellarg((string) ($config['port'] ?? 3306)),
            escapeshellarg($config['username'] ?? ''),
            escapeshellarg($config['password'] ?? ''),
            escapeshellarg($config['database'] ?? ''),
            escapeshellarg($chemin),
        );

        exec($commande, $sortie, $code);

        if ($code !== 0 || ! file_exists($chemin) || filesize($chemin) === 0) {
            @unlink($chemin);

            return false;
        }

        return true;
    }

    /** @return array<int, string> */
    private function toutesLesTables(): array
    {
        return collect(static::modules())
            ->flatMap(fn ($d) => $d['tables'])
            ->unique()
            ->values()
            ->all();
    }

    /**
     * Écrit un export SQL portable des tables demandées.
     *
     * ⚠️ Les valeurs passent par `PDO::quote`, jamais par une concaténation
     * naïve : un libellé contenant une apostrophe — « Poulet d'un jour » —
     * produirait un fichier SQL invalide, et l'on ne s'en apercevrait qu'au
     * moment de restaurer.
     *
     * @param  array<int, string>  $tables
     */
    private function ecrire(string $fichier, array $tables): void
    {
        $pdo = DB::connection()->getPdo();
        $lignes = [
            '-- Sauvegarde AgriERP — '.now()->toDateTimeString(),
            '-- Export de données uniquement : ce fichier ne contient PAS le schéma.',
            'SET FOREIGN_KEY_CHECKS=0;',
            '',
        ];

        foreach ($tables as $table) {
            if (! Schema::hasTable($table)) {
                continue;
            }

            $enregistrements = DB::table($table)->get();

            if ($enregistrements->isEmpty()) {
                continue;
            }

            $lignes[] = '-- Table : '.$table;

            foreach ($enregistrements as $enregistrement) {
                $colonnes = array_keys((array) $enregistrement);
                $valeurs = array_map(
                    fn ($v) => $v === null ? 'NULL' : $pdo->quote((string) $v),
                    array_values((array) $enregistrement),
                );

                $lignes[] = sprintf(
                    'INSERT INTO `%s` (`%s`) VALUES (%s);',
                    $table,
                    implode('`, `', $colonnes),
                    implode(', ', $valeurs),
                );
            }

            $lignes[] = '';
        }

        $lignes[] = 'SET FOREIGN_KEY_CHECKS=1;';

        Storage::disk('local')->put(
            self::DOSSIER.'/'.$fichier,
            implode(PHP_EOL, $lignes).PHP_EOL,
        );
    }
}
