<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 15.50 — MARQUE DE RÉINITIALISATION, servie au tirage.
 *
 * Un poste hors ligne au moment d'une réinitialisation garde toutes les données effacées sur le serveur, et
 * les renverrait à son prochain envoi (bandes, ventes, écritures ressuscitées). L'instant de la dernière
 * réinitialisation descend au tirage : le poste qui ne le connaît pas purge ses données d'activité avant
 * tout envoi, et le serveur refuse l'envoi d'un poste qui ne l'a pas encore vu.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->timestamp('data_reset_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->dropColumn('data_reset_at');
        });
    }
};
