<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket EX9 (11/11/2026) — archive figée de l'exercice à la clôture.
 *
 * Hors purge des 30 jours ; conservée 10 ans (Q6).
 * Pas de `updated_at` : ces enregistrements sont immuables.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('fiscal_year_archives', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('fiscal_year_id')->constrained('fiscal_years')->cascadeOnDelete();
            $table->timestamp('cloture_at');
            $table->json('bilan');
            $table->json('compte_resultat');
            $table->json('balance');
            $table->timestamp('created_at')->useCurrent();
            $table->index('fiscal_year_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('fiscal_year_archives');
    }
};
