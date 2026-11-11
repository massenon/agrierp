<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Sprint C — CLÔTURE DE CAISSE.
 *
 * Chaque clôture représente le rapprochement quotidien entre la caisse physique
 * et le total des ventes enregistrées. L'unicité `[closure_date, device_id]`
 * empêche de clôturer deux fois le même jour sur le même poste.
 * `device_id` nullable : une clôture faite depuis le web a `device_id = null`.
 *
 * PK UUID (table synchronisable, règle monorepo CLAUDE.md).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('cash_closures', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('fiscal_year_id')->constrained('fiscal_years');
            $table->date('closure_date');
            $table->string('device_id')->nullable();
            $table->decimal('ventes_especes', 15, 2)->default(0);
            $table->decimal('ventes_mobile_money', 15, 2)->default(0);
            $table->decimal('ventes_virement', 15, 2)->default(0);
            $table->decimal('fond_de_caisse', 15, 2)->default(0);
            $table->decimal('montant_compte', 15, 2)->default(0);
            $table->decimal('ecart', 15, 2)->default(0);
            $table->enum('statut', ['en_cours', 'validée', 'annulée'])->default('en_cours');
            $table->foreignUuid('accounting_entry_id')->nullable()->constrained('accounting_entries');
            $table->foreignId('created_by')->nullable()->constrained('users');
            $table->timestamps();

            // Un seul passage de caisse par jour par poste (null = web).
            $table->unique(['closure_date', 'device_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cash_closures');
    }
};
