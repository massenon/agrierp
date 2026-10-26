<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket DEP4 — COHÉRENCE DE SCHÉMA LARAVEL ↔ DRIFT pour la dépense à plusieurs lignes (`expenses`, `expense_lines`,
 * `cost_centers`).
 *
 * « Une table synchronisable modifiée côté Laravel (migrations) doit l'être aussi côté Flutter » (CLAUDE.md racine) :
 * ce test lit `agrierp_flutter/lib/core/database/app_database.dart` (les classes `Expenses`, `ExpenseLines`, `CostCenters`)
 * et le schéma RÉEL issu des migrations, et exige que chaque colonne d'un côté existe de l'autre — ou figure dans les
 * listes d'écarts ci-dessous, AVEC leur raison. Une colonne ajoutée d'un seul côté sans être déclarée fait rougir le test.
 */
class SchemaDepensesPosteTest extends TestCase
{
    use RefreshDatabase;

    /** Table Laravel → classe Drift. */
    private const TABLES = [
        'expenses' => 'Expenses',
        'expense_lines' => 'ExpenseLines',
        'cost_centers' => 'CostCenters',
    ];

    /** Colonnes du POSTE seul : raison. `with SyncColumns` apporte id, device_id, sync_status, updated_at. */
    private const POSTE_SEUL = [
        'expenses' => [
            'device_id' => 'poste d\'origine de la saisie (SyncColumns)',
            'sync_status' => 'file d\'envoi : pending, synced, conflict (SyncColumns)',
            'ecriture_refus' => 'refus de la pièce par le serveur, affiché sous la dépense (le web dit le refus tout de suite)',
        ],
        'expense_lines' => [],
        'cost_centers' => [],
    ];

    /** Colonnes du SERVEUR seul : raison. */
    private const SERVEUR_SEUL = [
        'expenses' => [
            'created_at' => 'horodatage technique du serveur (le poste garde `updated_at`)',
            'receipt_path' => 'le justificatif ne voyage pas : la synchronisation ne transporte aucun fichier',
        ],
        'expense_lines' => [
            'created_at' => 'horodatage technique : une ligne suit son en-tête, sans curseur propre',
            'updated_at' => 'idem',
        ],
        'cost_centers' => [
            'created_at' => 'horodatage technique du référentiel',
            'updated_at' => 'idem',
        ],
    ];

    /** Colonnes dont la NULLITÉ diffère, avec la raison. */
    private const NULLITE_DIFFERENTE = [
        'expenses.updated_at' => '`timestamps()` de Laravel est nullable ; le poste renseigne toujours l\'instant de saisie (SyncColumns)',
        'expenses.category' => 'nullable au serveur depuis DEP1 (la catégorie texte disparaît de la saisie) ; le poste garde du texte et écrit « » quand le serveur n\'en sert pas',
    ];

    /** @return array<string, array{nullable: bool}> les colonnes Drift d'une classe, par nom SQL */
    private function colonnesDrift(string $classe): array
    {
        $source = file_get_contents(base_path('../agrierp_flutter/lib/core/database/app_database.dart'));
        $this->assertNotFalse($source, 'app_database.dart introuvable : dépôt Flutter absent');

        $this->assertSame(1, preg_match('/class '.$classe.' extends Table( with SyncColumns)? \{(.*?)\n\}\n/s', $source, $m), "classe Drift {$classe} introuvable");
        $colonnes = [];
        if (trim($m[1]) !== '') {
            $colonnes += [
                'id' => ['nullable' => false], 'device_id' => ['nullable' => false],
                'sync_status' => ['nullable' => false], 'updated_at' => ['nullable' => false],
            ];
        }
        preg_match_all('/^\s*(?:Text|Int|Real|Bool|DateTime)Column get (\w+) =>(.*?);/ms', $m[2], $lignes, PREG_SET_ORDER);
        foreach ($lignes as $l) {
            $colonnes[Str::snake($l[1])] = ['nullable' => str_contains($l[2], '.nullable()')];
        }

        return $colonnes;
    }

    public function test_chaque_colonne_existe_des_deux_cotes_ou_est_declaree_avec_sa_raison(): void
    {
        foreach (self::TABLES as $table => $classe) {
            $this->assertTrue(Schema::hasTable($table), "table {$table} absente des migrations");
            $serveur = array_column(Schema::getColumns($table), null, 'name');
            $drift = $this->colonnesDrift($classe);

            foreach ($drift as $colonne => $_) {
                if (isset(self::POSTE_SEUL[$table][$colonne])) {
                    $this->assertArrayNotHasKey($colonne, $serveur, "{$table}.{$colonne} est déclarée « poste seul » mais existe au serveur : retirer la déclaration");

                    continue;
                }
                $this->assertArrayHasKey($colonne, $serveur, "{$table}.{$colonne} existe dans Drift ({$classe}) mais pas dans les migrations Laravel : migration manquante, ou colonne propre au poste à déclarer");
            }
            foreach ($serveur as $colonne => $_) {
                if (isset(self::SERVEUR_SEUL[$table][$colonne])) {
                    $this->assertArrayNotHasKey($colonne, $drift, "{$table}.{$colonne} est déclarée « serveur seul » mais existe dans Drift : retirer la déclaration");

                    continue;
                }
                $this->assertArrayHasKey($colonne, $drift, "{$table}.{$colonne} existe au serveur mais pas dans Drift ({$classe}) : régénérer (`dart run build_runner build`) ou déclarer l'écart");
            }
        }
    }

    public function test_la_nullite_des_colonnes_communes_est_la_meme(): void
    {
        foreach (self::TABLES as $table => $classe) {
            $serveur = array_column(Schema::getColumns($table), null, 'name');
            foreach ($this->colonnesDrift($classe) as $colonne => $infos) {
                if (! isset($serveur[$colonne]) || isset(self::NULLITE_DIFFERENTE["{$table}.{$colonne}"]) || $colonne === 'id') {
                    continue;
                }
                $this->assertSame(
                    (bool) $serveur[$colonne]['nullable'],
                    $infos['nullable'],
                    "{$table}.{$colonne} : nullité différente (serveur ".($serveur[$colonne]['nullable'] ? 'nullable' : 'non nulle').', Drift '.($infos['nullable'] ? 'nullable' : 'non nulle').')'
                );
            }
        }
    }

    public function test_le_palier_drift_est_declare_et_ses_tables_servies_au_tirage(): void
    {
        $source = file_get_contents(base_path('../agrierp_flutter/lib/core/database/app_database.dart'));
        // ARC3 : la Corbeille porte le schéma à 58 (57 devis, 59 dépenses, 60 modules sont réservés) ; le palier 56 des
        // dépenses reste dans la chaîne (`from < 56`) : le numéro courant ne peut que croître.
        preg_match('/int get schemaVersion => (\d+);/', $source, $version);
        $this->assertGreaterThanOrEqual(56, (int) ($version[1] ?? 0), 'schéma Drift 56 au moins (le palier des dépenses est dans la chaîne)');
        $this->assertStringContainsString('if (from < 56)', $source);
        foreach (['expense_lines', 'cost_centers'] as $table) {
            $this->assertArrayHasKey($table, \App\Http\Controllers\Api\SyncController::PERMISSIONS_DE_TIRAGE, "{$table} doit être servie au tirage");
        }
    }
}
