<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ (ticket 2.8) : absente des 26 migrations documentées.
 * Nécessaire pour l'onglet "Types de Provende" de `parametres-elevage.html`
 * — catalogue distinct de `products` (Sprint 2.2) : la provende est
 * délibérément tarifée au kilogramme ("Prix Indicatif FCFA/Kg"), à
 * l'inverse de `products` qui interdit explicitement toute unité de poids
 * (Document 00 §5.3 — "toujours une unité de pièce/comptage"). Ce sont
 * deux concepts distincts : `products` = ce que la ferme VEND,
 * `feed_types` = ce que la ferme ACHÈTE/CONSOMME pour nourrir le cheptel
 * (alimente le calcul d'autonomie alimentaire, Document 05).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('feed_types', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('name', 150);
            $table->foreignUuid('species_id')->nullable()->constrained('livestock_species')->nullOnDelete();
            $table->decimal('standard_bag_weight_kg', 8, 2);
            $table->decimal('price_per_kg', 10, 2);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('feed_types');
    }
};
