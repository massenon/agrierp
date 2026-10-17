<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 10.1 (Sprint 10) — reprise exacte de FULL_MIGRATIONS_DATABASE.md
 * §14. Complète le FK différé annoncé explicitement depuis le ticket 3.1 :
 * `livestock_lots.cost_center_id` existait déjà en uuid nullable SANS
 * contrainte (la table cible n'existait pas encore) — la contrainte est
 * ajoutée maintenant que `cost_centers` existe, jamais oubliée.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('cost_centers', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('label', 100);
            $table->enum('type', ['filiere', 'lot']);
            $table->foreignUuid('parent_species_id')->nullable()->constrained('livestock_species')->nullOnDelete();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        Schema::table('livestock_lots', function (Blueprint $table) {
            $table->foreign('cost_center_id')->references('id')->on('cost_centers')->nullOnDelete();
        });

        // ⚠️ AJOUT AU-DELÀ DE LA REPRISE DOCUMENTÉE (justifié) : `sale_lines.cost_center_id`
        // (ticket 4.1) était également différée pour la même raison exacte
        // (table cible inexistante) — la contrainte est complétée ici par
        // cohérence, jamais laissée orpheline alors que la table cible existe
        // désormais.
        Schema::table('sale_lines', function (Blueprint $table) {
            $table->foreign('cost_center_id')->references('id')->on('cost_centers')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('sale_lines', function (Blueprint $table) {
            $table->dropForeign(['cost_center_id']);
        });
        Schema::table('livestock_lots', function (Blueprint $table) {
            $table->dropForeign(['cost_center_id']);
        });
        Schema::dropIfExists('cost_centers');
    }
};
