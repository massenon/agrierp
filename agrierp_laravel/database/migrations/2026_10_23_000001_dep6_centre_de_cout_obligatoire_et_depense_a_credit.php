<?php

use App\Models\CostCenter;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Tickets DEP6 et DEP7 (PRD `docs/prd/depenses-multilignes.md`, § 11 — décisions du client du 21/10/2026 : DEP-Q1 « le
 * centre de coût doit devenir obligatoire », DEP-Q3 « une dépense à un fournisseur doit créer une dette »).
 *
 * 1. CENTRE DE COÛT OBLIGATOIRE (DEP6). Le dépôt n'avait AUCUN centre « Général / Commun » (`cost_centers` : les cinq
 *    filières du semoir) : « Général » (type `filiere`) est créé ICI, et les dépenses déjà saisies sans centre y sont
 *    rangées — aucune n'est perdue, aucune n'est modifiée autrement. Leurs ÉCRITURES ne sont JAMAIS réécrites (une pièce
 *    passée est immuable) : seule l'en-tête de la dépense porte le centre. `updated_at` est touché pour que les postes
 *    reçoivent le centre au prochain tirage. Rejouable : aucun second « Général », aucune erreur.
 *
 * 2. DÉPENSE À CRÉDIT (DEP7). `expenses.on_credit` (la dépense n'est pas payée comptant : elle crédite le 401 et ouvre une
 *    dette) ; `expenses.treasury_account_id` devient NULLABLE (une dépense à crédit ne touche aucune trésorerie) ;
 *    `payables.expense_id` (la dette d'une dépense, à côté de `purchase_id` pour celle d'un achat).
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('expenses', 'on_credit')) {
            Schema::table('expenses', function (Blueprint $table) {
                $table->boolean('on_credit')->default(false)->after('supplier_id');
            });
        }

        if ($this->tresorerieEstObligatoire()) {
            Schema::table('expenses', function (Blueprint $table) {
                $table->uuid('treasury_account_id')->nullable()->change();
            });
        }

        if (! Schema::hasColumn('payables', 'expense_id')) {
            Schema::table('payables', function (Blueprint $table) {
                $table->foreignUuid('expense_id')->nullable()->after('purchase_id')->constrained('expenses')->nullOnDelete();
            });
        }

        // Le centre par défaut et le rangement des dépenses existantes : voir le docblock.
        $general = CostCenter::general();
        DB::table('expenses')->whereNull('cost_center_id')->update(['cost_center_id' => $general->id, 'updated_at' => now()]);
    }

    public function down(): void
    {
        Schema::table('payables', function (Blueprint $table) {
            $table->dropConstrainedForeignId('expense_id');
        });

        Schema::table('expenses', function (Blueprint $table) {
            $table->dropColumn('on_credit');
        });
        // `treasury_account_id` reste nullable : le remettre obligatoire échouerait sur une dépense à crédit déjà saisie.
    }

    private function tresorerieEstObligatoire(): bool
    {
        foreach (Schema::getColumns('expenses') as $colonne) {
            if ($colonne['name'] === 'treasury_account_id') {
                return ! $colonne['nullable'];
            }
        }

        return true;
    }
};
