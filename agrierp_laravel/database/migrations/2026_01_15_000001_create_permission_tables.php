<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ⚠️ NOTE DE FIABILITÉ (Sprint 0, ticket 0.1) — À LIRE AVANT UTILISATION
 *
 * Ce fichier reproduit la structure standard publiée par
 * `spatie/laravel-permission` (commande `php artisan vendor:publish
 * --provider="Spatie\Permission\PermissionServiceProvider"`), adaptée pour
 * des clés UUID (`uuidMorphs('model')` au lieu de `morphs('model')` —
 * cohérence avec `users.id` UUID, voir docblock de la migration `users`).
 *
 * L'environnement de génération de ce paquet n'a pas d'accès réseau à
 * Packagist (voir avertissement de session) : cette migration n'a donc PAS
 * pu être vérifiée par une exécution réelle de `vendor:publish` contre la
 * version exacte du paquet qui sera installée localement. Avant le premier
 * `php artisan migrate`, comparer ce fichier à la sortie réelle de :
 *   composer require spatie/laravel-permission
 *   php artisan vendor:publish --provider="Spatie\Permission\PermissionServiceProvider" --tag="permission-migrations"
 * et ne conserver qu'UNE SEULE version (supprimer le doublon) si un écart
 * de structure apparaît avec la version effectivement installée.
 */
return new class extends Migration
{
    public function up(): void
    {
        $teams = config('permission.teams', false);
        $tableNames = config('permission.table_names');
        $columnNames = config('permission.column_names');
        $pivotRole = $columnNames['role_pivot_key'] ?? 'role_id';
        $pivotPermission = $columnNames['permission_pivot_key'] ?? 'permission_id';

        if (empty($tableNames)) {
            throw new \Exception('Publier le fichier de configuration Permission avant de lancer les migrations.');
        }

        Schema::create($tableNames['permissions'], function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('name');
            $table->string('guard_name');
            $table->timestamps();
            $table->unique(['name', 'guard_name']);
        });

        Schema::create($tableNames['roles'], function (Blueprint $table) use ($teams) {
            $table->uuid('id')->primary();
            if ($teams || config('permission.testing')) {
                $table->unsignedBigInteger(config('permission.column_names.team_foreign_key'))->nullable();
                $table->index(config('permission.column_names.team_foreign_key'), 'roles_team_foreign_key_index');
            }
            $table->string('name');
            $table->string('guard_name');
            $table->timestamps();
            if ($teams || config('permission.testing')) {
                $table->unique([config('permission.column_names.team_foreign_key'), 'name', 'guard_name']);
            } else {
                $table->unique(['name', 'guard_name']);
            }
        });

        Schema::create($tableNames['model_has_permissions'], function (Blueprint $table) use ($tableNames, $columnNames, $pivotPermission, $teams) {
            $table->uuid($pivotPermission);
            $table->uuidMorphs('model');
            $table->foreign($pivotPermission)
                ->references('id')
                ->on($tableNames['permissions'])
                ->onDelete('cascade');
            if ($teams) {
                $table->unsignedBigInteger(config('permission.column_names.team_foreign_key'));
                $table->index(config('permission.column_names.team_foreign_key'), 'model_has_permissions_team_foreign_key_index');
                $table->primary(
                    [config('permission.column_names.team_foreign_key'), $pivotPermission, 'model_id', 'model_type'],
                    'model_has_permissions_permission_model_type_primary'
                );
            } else {
                $table->primary(
                    [$pivotPermission, 'model_id', 'model_type'],
                    'model_has_permissions_permission_model_type_primary'
                );
            }
        });

        Schema::create($tableNames['model_has_roles'], function (Blueprint $table) use ($tableNames, $columnNames, $pivotRole, $teams) {
            $table->uuid($pivotRole);
            $table->uuidMorphs('model');
            $table->foreign($pivotRole)
                ->references('id')
                ->on($tableNames['roles'])
                ->onDelete('cascade');
            if ($teams) {
                $table->unsignedBigInteger(config('permission.column_names.team_foreign_key'));
                $table->index(config('permission.column_names.team_foreign_key'), 'model_has_roles_team_foreign_key_index');
                $table->primary(
                    [config('permission.column_names.team_foreign_key'), $pivotRole, 'model_id', 'model_type'],
                    'model_has_roles_role_model_type_primary'
                );
            } else {
                $table->primary(
                    [$pivotRole, 'model_id', 'model_type'],
                    'model_has_roles_role_model_type_primary'
                );
            }
        });

        Schema::create($tableNames['role_has_permissions'], function (Blueprint $table) use ($tableNames, $pivotRole, $pivotPermission) {
            $table->uuid($pivotPermission);
            $table->uuid($pivotRole);

            $table->foreign($pivotPermission)
                ->references('id')
                ->on($tableNames['permissions'])
                ->onDelete('cascade');

            $table->foreign($pivotRole)
                ->references('id')
                ->on($tableNames['roles'])
                ->onDelete('cascade');

            $table->primary([$pivotPermission, $pivotRole], 'role_has_permissions_permission_id_role_id_primary');
        });

        app('cache')
            ->store(config('permission.cache.store') !== 'default' ? config('permission.cache.store') : null)
            ->forget(config('permission.cache.key'));
    }

    public function down(): void
    {
        $tableNames = config('permission.table_names');

        if (empty($tableNames)) {
            return;
        }

        Schema::drop($tableNames['role_has_permissions']);
        Schema::drop($tableNames['model_has_roles']);
        Schema::drop($tableNames['model_has_permissions']);
        Schema::drop($tableNames['roles']);
        Schema::drop($tableNames['permissions']);
    }
};
