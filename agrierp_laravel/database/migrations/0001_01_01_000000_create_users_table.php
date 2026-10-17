<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * DÉCISION ARCHITECTURALE DOCUMENTÉE (Sprint 0, ticket 0.1) :
 * `users.id` est un UUID, et non le bigIncrements par défaut de Laravel.
 *
 * Justification :
 * - Les 26 migrations métier (FULL_MIGRATIONS_DATABASE.md) utilisent
 *   toutes `$table->uuid('id')->primary()` — un seul type de clé primaire
 *   dans tout le schéma (cohérence, Document 02 §2.5 "un seul point de
 *   vérité").
 * - Document 06 §16.15 (`LARAVEL_SYNC_FLUTTER.md`) exige `uuidMorphs()`
 *   plutôt que `morphs()` pour toute table Sanctum liée à une clé UUID —
 *   ce qui suppose que `users` (table `tokenable` de Sanctum) est déjà en
 *   UUID ; sinon cette exigence n'aurait pas de sens.
 * - `audit_logs`, `notifications` et toute table journalisant un
 *   utilisateur référencent `user_id` en UUID pour rester cohérentes avec
 *   le reste du schéma (Document 03 §3.23).
 *
 * En conséquence, la migration Spatie Permission (fichier
 * `..._create_permission_tables.php` de ce même dossier) utilise
 * `uuidMorphs('model')` au lieu de `morphs('model')`, et
 * `config/permission.php` déclare `column_names.model_morph_key = model_id`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('users', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('name');
            $table->string('email')->unique();
            $table->timestamp('email_verified_at')->nullable();
            $table->string('password');
            $table->boolean('is_active')->default(true);
            $table->rememberToken();
            $table->timestamps();
        });

        Schema::create('password_reset_tokens', function (Blueprint $table) {
            $table->string('email')->primary();
            $table->string('token');
            $table->timestamp('created_at')->nullable();
        });

        Schema::create('sessions', function (Blueprint $table) {
            $table->string('id')->primary();
            $table->uuid('user_id')->nullable()->index();
            $table->string('ip_address', 45)->nullable();
            $table->text('user_agent')->nullable();
            $table->longText('payload');
            $table->integer('last_activity')->index();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('users');
        Schema::dropIfExists('password_reset_tokens');
        Schema::dropIfExists('sessions');
    }
};
