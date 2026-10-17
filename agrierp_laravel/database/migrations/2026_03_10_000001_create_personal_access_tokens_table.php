<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * 🔴→✅ GAP CRITIQUE TROUVÉ EN VÉRIFIANT LA VRAIE MIGRATION SANCTUM
 * (clonée depuis github.com/laravel/sanctum avant toute conclusion,
 * jamais supposée) : la migration par défaut de Sanctum utilise
 * `$table->morphs('tokenable')`, qui crée un `tokenable_id` en
 * `BIGINT` auto-incrémenté. Ce projet utilise des UUID partout
 * (`users.id` inclus, décision documentée au ticket 0.1) — publier la
 * migration par défaut via `vendor:publish` aurait créé un
 * `tokenable_id` de type incompatible avec `users.id`, cassant
 * silencieusement l'association jeton↔utilisateur (aucune erreur au
 * `migrate`, juste une colonne qui ne peut jamais correspondre).
 *
 * Cette migration remplace la publication par défaut — jamais lancer
 * `php artisan vendor:publish --provider="Laravel\Sanctum\SanctumServiceProvider"`
 * pour les migrations sur ce projet, cette migration-ci suffit et est
 * déjà correcte.
 *
 * Le docblock de `0001_01_01_000000_create_users_table.php` (Sprint 0,
 * ticket 0.1) anticipait déjà exactement cette exigence
 * ("Document 06 §16.15 exige uuidMorphs() plutôt que morphs() pour
 * toute table Sanctum liée à une clé UUID") — jamais implémentée avant
 * ce ticket puisque Sanctum lui-même n'existait pas encore dans le
 * projet à ce moment-là.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('personal_access_tokens', function (Blueprint $table) {
            $table->id();
            $table->uuidMorphs('tokenable');
            $table->text('name');
            $table->string('token', 64)->unique();
            $table->text('abilities')->nullable();
            $table->timestamp('last_used_at')->nullable();
            $table->timestamp('expires_at')->nullable()->index();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('personal_access_tokens');
    }
};
