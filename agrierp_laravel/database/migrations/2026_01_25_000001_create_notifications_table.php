<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ (ticket 1.7, Sprint 1) : `FULL_MIGRATIONS_DATABASE.md`
 * §25 ne comporte pas de colonne de gravité, alors que `notifications.html`
 * (source de vérité n°1, Document 00 §1) affiche une colonne "Gravité"
 * indépendante à 3 niveaux (Critique/Moyen/Info) avec un code couleur par
 * ligne — non déductible de façon fiable de la seule colonne `type` (deux
 * notifications de même `type` peuvent avoir une gravité différente en
 * pratique, ex. seuil de stock proche vs déjà atteint). Colonne `severity`
 * ajoutée en conséquence, le reste de la table reprend `FULL_MIGRATIONS_
 * DATABASE.md` §25 à l'identique.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('notifications', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->nullable()->constrained('users')->cascadeOnDelete();
            $table->string('target_role', 20)->nullable();
            $table->enum('type', ['stock_low', 'high_mortality', 'payment_due', 'fiscal_year_reminder', 'prophylaxis_due', 'system']);
            $table->enum('severity', ['critique', 'moyen', 'info'])->default('info');
            $table->string('title', 150);
            $table->text('message');
            $table->string('icon', 50)->nullable();
            $table->string('link_url', 255)->nullable();
            $table->boolean('is_read')->default(false);
            $table->timestamp('read_at')->nullable();
            $table->timestamp('created_at')->useCurrent();
            $table->index(['user_id', 'is_read']);
            $table->index(['target_role', 'is_read']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('notifications');
    }
};
