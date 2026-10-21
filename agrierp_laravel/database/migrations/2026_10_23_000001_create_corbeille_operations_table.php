<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket ARC1 (PRD `docs/prd/archives.md`) — LE JOURNAL DE LA CORBEILLE.
 *
 * Une ligne par restauration ou suppression définitive : QUI (`user_id`), QUOI (`type`, `element_id`, `titre`), QUAND,
 * depuis quel poste (`device_id`), avec quelle issue (`accepte` / `refuse`, le motif du refus).
 *
 * Pourquoi une table en plus de `audit_logs` : le journal d'audit ne retient ni l'enregistrement visé ni son titre. Une
 * suppression définitive est IRRÉVERSIBLE : la ligne supprimée n'est plus là pour dire ce qu'elle était, d'où `titre`
 * (copié AVANT l'effacement). C'est aussi la mémoire des demandes du poste (`id` = UUID de la demande née sur le
 * poste) : une demande renvoyée après un acquittement perdu n'est jamais rejouée.
 *
 * Table propre au SERVEUR : jamais tirée ni poussée. Migration sûre : ne recrée rien si elle existe déjà.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('corbeille_operations')) {
            return;
        }

        Schema::create('corbeille_operations', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('user_id')->nullable()->index();
            $table->string('action', 20);              // restaurer | supprimer
            $table->string('type', 40);
            $table->uuid('element_id');
            $table->string('titre', 255)->nullable();
            $table->string('issue', 20);               // accepte | refuse
            $table->text('motif')->nullable();
            $table->string('device_id', 255)->nullable();
            $table->timestamps();

            $table->index(['type', 'element_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('corbeille_operations');
    }
};
