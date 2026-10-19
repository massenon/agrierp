<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket S-T6 — DERNIER CONTRÔLE DE COHÉRENCE DE CHAQUE POSTE.
 *
 * Le contrôle se fait AU POSTE : il demande au serveur ses comptes par table et par jour
 * (`GET /api/sync/coherence`) et les compare aux siens. Le serveur note seulement QUAND chaque poste l'a demandé, pour
 * que la modale « Synchronisation » du web montre le dernier contrôle de chacun. Le résultat de la comparaison reste au
 * poste (son écran Synchronisation) : le serveur ne connaît pas les chiffres du poste.
 *
 * Table propre au SERVEUR : jamais tirée ni poussée.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('controles_coherence')) {
            return;
        }

        Schema::create('controles_coherence', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('poste', 255);
            $table->date('depuis');
            $table->timestamp('created_at')->useCurrent();

            $table->index(['poste', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('controles_coherence');
    }
};
