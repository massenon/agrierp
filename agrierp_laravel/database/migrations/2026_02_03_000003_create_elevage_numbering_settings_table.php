<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ (ticket 2.8) : absente des 26 migrations documentées.
 * `company_settings` (§22) est scopée à l'identité de l'entreprise et au
 * SMTP — une préoccupation distincte de la numérotation des bandes/sujets
 * d'élevage. Plutôt que de mélanger deux responsabilités dans une même
 * table (et de faire dépendre ce ticket de `company_settings`, prévue à
 * un sprint ultérieur — Paramètres), table dédiée à une seule ligne
 * (singleton), sur le même principe.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('elevage_numbering_settings', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('bande_format', 50)->default('BANDE B');
            $table->string('lapine_prefix', 10)->default('R');
            $table->string('male_prefix', 10)->default('M');
            $table->string('truie_prefix', 10)->default('T');
            $table->string('verrat_prefix', 10)->default('V');
            $table->string('portee_prefix', 10)->default('P');
            $table->string('volaille_prefix', 20)->default('LOT-VOL');
            $table->string('parc_prefix', 20)->default('PARC');
            $table->string('escargot_prefix', 20)->default('FOSSE');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('elevage_numbering_settings');
    }
};
