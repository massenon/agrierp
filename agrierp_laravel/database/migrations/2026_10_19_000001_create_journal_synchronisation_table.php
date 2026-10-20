<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket H3 — JOURNAL DE SYNCHRONISATION DES POSTES (PRD `docs/prd/synchronisation-barre-superieure.md`, EF12).
 *
 * 🔴 Le serveur ne savait presque rien de ses postes : un envoi laissait une ligne `api.sync_push` sans poste ni
 * compteur, un tirage ne laissait rien. L'administrateur ne pouvait pas voir quel poste n'avait rien envoyé depuis
 * trois jours, ni lequel accumulait des refus.
 *
 * Table propre au SERVEUR : jamais tirée ni poussée. `poste` = nom du jeton Sanctum, c'est-à-dire l'identifiant du
 * poste (`AuthController` crée le jeton sous `device_name`).
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('journal_synchronisation')) {
            return;
        }

        Schema::create('journal_synchronisation', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('poste', 255);
            $table->enum('sens', ['tirage', 'envoi']);
            $table->unsignedInteger('nb_recus')->default(0);
            $table->unsignedInteger('nb_acceptes')->default(0);
            $table->unsignedInteger('nb_refuses')->default(0);
            $table->timestamp('created_at')->useCurrent();

            $table->index(['poste', 'sens', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('journal_synchronisation');
    }
};
