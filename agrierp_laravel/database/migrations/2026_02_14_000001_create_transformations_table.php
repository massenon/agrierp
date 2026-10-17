<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * `accounting_entry_id` : uuid nullable SANS contrainte de clé étrangère
 * pour l'instant, comme `livestock_lots.cost_center_id` (ticket 3.1) —
 * aucune table d'écritures comptables n'existe encore (Sprint 10). La
 * contrainte FK sera ajoutée par une migration `alter` dédiée à ce moment.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('transformations', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('lot_id')->constrained('livestock_lots')->restrictOnDelete();
            $table->foreignUuid('product_id')->constrained('products')->restrictOnDelete();
            $table->unsignedInteger('qty_animals');
            $table->decimal('qty_produced', 10, 2);
            $table->foreignUuid('operator_id')->constrained('users')->restrictOnDelete();
            $table->date('transformation_date');
            $table->uuid('accounting_entry_id')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('transformations');
    }
};
