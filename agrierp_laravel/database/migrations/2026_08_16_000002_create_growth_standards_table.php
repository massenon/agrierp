<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.9 (Sprint 14) — barème d'objectifs de croissance (GMQ), nécessaire
 * à la colonne « Statut vs Objectif » d'`analyse-croissance.html`.
 *
 * Le prototype écrit ces objectifs EN DUR sur chaque ligne
 * (`objectifMin`/`objectifMax`). Une valeur figée par lot ne survit pas à un
 * élevage réel : le barème est donc externalisé, exactement sur le modèle
 * déjà établi par `feed_ration_standards` (ticket 2.7) — même clé
 * `species_code` + `stage_label`, même logique de référentiel paramétrable.
 *
 * Les valeurs semées proviennent des objectifs réels du prototype, jamais
 * inventées — même discipline que le barème Héliciculture retrouvé dans
 * `fiche-escargots.html`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('growth_standards', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('species_code', 20);
            $table->string('stage_label', 100);
            $table->unsignedInteger('gmq_min_g_per_day');
            $table->unsignedInteger('gmq_max_g_per_day');
            $table->timestamps();

            $table->index(['species_code', 'stage_label']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('growth_standards');
    }
};
