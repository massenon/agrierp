<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ (ticket 2.8) : absente des 26 migrations documentées.
 * `veterinary_calendar_events` (§19, `FULL_MIGRATIONS_DATABASE.md`) est
 * une table d'INSTANCES réelles liées à un `lot_id` précis (Sprint 3).
 * L'onglet "Calendriers de Prophylaxie" de `parametres-elevage.html` est
 * un BARÈME / MODÈLE par espèce, indépendant de tout lot — exactement la
 * même distinction que `feed_ration_standards` vs les saisies réelles de
 * consommation. Ce barème alimentera la génération automatique
 * d'échéances (`veterinary_calendar_events`) une fois un lot créé
 * (Sprint 3) — non implémenté ici, hors périmètre de ce ticket.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('prophylaxis_schedule_standards', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('species_code', 20);
            $table->string('period_label', 100);
            $table->string('treatment', 150);
            $table->string('product_recommended', 150);
            $table->string('dosage', 150);
            $table->unsignedSmallInteger('withdrawal_days')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->index('species_code');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('prophylaxis_schedule_standards');
    }
};
