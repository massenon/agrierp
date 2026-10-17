<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.56 (Sprint 14) — BASCULE « MODE DEMONSTRATION ».
 *
 * Commande la visibilite de l'onglet de reinitialisation des donnees.
 *
 * ⚠️ FAUX PAR DEFAUT, ET C'EST LE POINT ESSENTIEL. Une exploitation en
 * production ne doit pas porter un bouton d'effacement accessible : la valeur
 * par defaut est celle qui protege, jamais celle qui arrange la demonstration.
 * Activer la bascule est un acte delibere, reserve a l'administrateur et
 * journalise.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->boolean('demo_mode_enabled')->default(false);
        });
    }

    public function down(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->dropColumn('demo_mode_enabled');
        });
    }
};
