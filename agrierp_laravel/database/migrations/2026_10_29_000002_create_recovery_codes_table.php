<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket MDP-1 — CODE DE SECOURS DE L'ADMINISTRATEUR (si le dernier administrateur oublie son mot de passe).
 *
 * Table dédiée plutôt qu'une colonne de `users` : le code appartient à l'INSTALLATION (un seul code actif à la fois,
 * imprimé et rangé au coffre), pas à un compte ; il garde la trace des codes remplacés ou consommés.
 *
 * ⚠️ Seule l'EMPREINTE (SHA-256 du code normalisé) est stockée, jamais le code : 24 caractères tirés d'un alphabet de 31
 * symboles font environ 119 bits, un hachage rapide suffit et ne dépend pas de `APP_KEY` (une restauration sur un autre
 * serveur garde le code valable). Table NON synchronisée (jamais servie au poste).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('recovery_codes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('empreinte', 64);
            // Instant où le code a été consommé ou remplacé ; NULL = code actif.
            $table->timestamp('used_at')->nullable();
            $table->string('used_reason', 20)->nullable(); // 'utilise' | 'remplace'
            $table->timestamp('created_at')->nullable();
            $table->index('used_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('recovery_codes');
    }
};
