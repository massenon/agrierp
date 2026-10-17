<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * DÉCISION DE SÉQUENCEMENT DOCUMENTÉE (ticket 1.2, Sprint 1) :
 * `FULL_MIGRATIONS_DATABASE.md` §23 place cette table en position 23/26
 * dans l'ordre de dépendance général (Document 06 §2.2, groupe "RH &
 * Système", après la plupart des tables métier). Elle est créée ICI, dès
 * le ticket 1.2, par nécessité : Document 06 §12 exige la journalisation
 * de "toute action sensible (connexion, déconnexion, clôture d'exercice,
 * modification RBAC...)" — une exigence qui s'applique dès le premier
 * écran d'authentification, pas seulement à partir du Sprint où le reste
 * du groupe "RH & Système" est construit. Reporter cette table aurait
 * signifié soit ignorer une exigence de sécurité explicite, soit journaliser
 * "à moitié" (Document 00 §2.2, zéro fonctionnalité inachevée) — les deux
 * proscrits. Code repris à l'identique de FULL_MIGRATIONS_DATABASE.md,
 * aucune colonne ajoutée ni retirée.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('audit_logs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('action', 150);
            $table->string('module', 100)->nullable();
            $table->string('ip_address', 45)->nullable();
            $table->timestamp('created_at')->useCurrent();
            $table->index(['user_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('audit_logs');
    }
};
