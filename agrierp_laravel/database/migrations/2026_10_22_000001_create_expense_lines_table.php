<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket DEP1 (PRD `docs/prd/depenses-multilignes.md`) — UNE DÉPENSE, PLUSIEURS LIGNES.
 *
 * `expenses` devient l'EN-TÊTE (date, mode, trésorerie, centre de coût, fournisseur ou bénéficiaire, auteur, pièce) ;
 * `expense_lines` porte chaque achat (libellé, COMPTE DE CHARGE du plan, montant). `expenses.amount` reste la colonne du
 * TOTAL, maintenue égale à la somme des lignes par `SaisieDepenseAction` (jamais saisie) ; `expenses.label` reste le
 * résumé : les rapports, le Tableau de bord et les KPI qui les lisent ne changent pas.
 *
 * ⚠️ `category` devient NULLABLE : la catégorie texte disparaît de la saisie au profit du compte de charge de la ligne.
 * La colonne est conservée (compte de la première ligne) pour les postes non encore migrés, qui la lisent au tirage.
 *
 * Clés en UUID (postes hors ligne). Aucun effacement physique d'une dépense : les lignes suivent leur en-tête.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('expenses', function (Blueprint $table) {
            $table->string('category', 100)->nullable()->change();
            $table->string('payment_mode', 20)->nullable()->after('treasury_account_id');
            $table->foreignUuid('cost_center_id')->nullable()->after('payment_mode')->constrained('cost_centers')->nullOnDelete();
            $table->foreignUuid('supplier_id')->nullable()->after('cost_center_id')->constrained('suppliers')->nullOnDelete();
            $table->string('beneficiary', 150)->nullable()->after('supplier_id');
            $table->foreignUuid('created_by')->nullable()->after('beneficiary')->constrained('users')->nullOnDelete();
        });

        Schema::create('expense_lines', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('expense_id')->constrained('expenses')->cascadeOnDelete();
            $table->unsignedSmallInteger('position')->default(0);
            $table->string('label', 255);
            $table->foreignUuid('charge_account_id')->constrained('chart_of_accounts')->restrictOnDelete();
            $table->decimal('amount', 14, 2);
            $table->timestamps();

            $table->index(['expense_id', 'position']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('expense_lines');

        Schema::table('expenses', function (Blueprint $table) {
            $table->dropConstrainedForeignId('created_by');
            $table->dropColumn('beneficiary');
            $table->dropConstrainedForeignId('supplier_id');
            $table->dropConstrainedForeignId('cost_center_id');
            $table->dropColumn('payment_mode');
        });
    }
};
