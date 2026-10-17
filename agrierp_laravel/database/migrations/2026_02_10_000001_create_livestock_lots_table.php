<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * `cost_center_id` : uuid nullable SANS contrainte de clé étrangère pour
 * l'instant — reprend à l'identique la note du document source
 * ("FK ajoutée migration 15, cost_centers créée après"). `cost_centers`
 * n'existe pas encore à ce point du plan (Sprint 10, Comptabilité) ; la
 * contrainte FK sera ajoutée par une migration `alter` dédiée quand ce
 * sprint sera atteint, jamais en avance sur sa propre table.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('livestock_lots', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('code', 50)->unique();
            $table->foreignUuid('species_id')->constrained('livestock_species')->restrictOnDelete();
            $table->enum('stage', ['reproduction', 'croissance', 'ponte', 'engraissement']);
            $table->unsignedInteger('initial_quantity');
            $table->unsignedInteger('current_quantity');
            $table->date('created_date');
            $table->enum('status', ['actif', 'cloture'])->default('actif');
            $table->uuid('cost_center_id')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->index(['species_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('livestock_lots');
    }
};
