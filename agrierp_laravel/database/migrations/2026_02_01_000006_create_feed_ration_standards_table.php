<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Table absente de la liste des 26 migrations documentées
 * (`FULL_MIGRATIONS_DATABASE.md`) mais explicitement requise par
 * `SEEDER_TEST.md` §4, qui en donne la structure exacte : "table
 * `feed_ration_standards`... à ajouter en migration 27 si pas déjà fait,
 * colonnes : id, species_code, stage_label, ration_g_per_day, timestamps."
 * Créée ici en suivant cette instruction à la lettre.
 *
 * `species_code` est une chaîne (ex. 'cuniculture'), pas une clé étrangère
 * vers `livestock_species.id` — c'est délibéré : le seeder prêt à l'emploi
 * (`FeedRationStandardsSeeder`, code déjà validé) associe directement par
 * `code`, jamais par UUID. Conservé tel quel (hiérarchie des sources,
 * Document 00 §2 : le code déjà validé fait foi).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('feed_ration_standards', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('species_code', 20);
            $table->string('stage_label', 100);
            $table->unsignedInteger('ration_g_per_day');
            $table->timestamps();
            $table->index('species_code');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('feed_ration_standards');
    }
};
