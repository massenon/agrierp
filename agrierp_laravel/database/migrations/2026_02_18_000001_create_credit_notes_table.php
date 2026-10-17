<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DE SCHÉMA DOCUMENTÉ (ticket 4.5) : `FULL_MIGRATIONS_DATABASE.md`
 * documente `credit_notes` a minima (`sale_id`, `amount`, `reason`). Le
 * prototype réel (`retours-avoirs.html`) implémente un assistant en 5
 * étapes (Facture → Articles → Motif → Inspection → Validation) avec une
 * décision Réintégré/Réforme par retour (impact réel sur le stock) et un
 * statut de traitement (En attente/Traité) — aucun des deux n'est
 * représentable avec le schéma minimal documenté. Colonnes ajoutées en
 * conséquence : `credit_note_number`, `product_id`, `qty`, `decision`,
 * `status`, `inspection_notes`. Base documentée conservée intégralement
 * (`sale_id`, `amount`, `reason`).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('credit_notes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('credit_note_number', 30)->unique();
            $table->foreignUuid('sale_id')->constrained('sales')->restrictOnDelete();
            $table->foreignUuid('product_id')->nullable()->constrained('products')->nullOnDelete();
            $table->decimal('qty', 10, 2)->nullable();
            $table->decimal('amount', 14, 2);
            $table->text('reason')->nullable();
            $table->enum('decision', ['reintegre', 'reforme'])->nullable();
            $table->text('inspection_notes')->nullable();
            $table->enum('status', ['en_attente', 'traite'])->default('en_attente');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('credit_notes');
    }
};
