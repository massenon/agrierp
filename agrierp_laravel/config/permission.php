<?php

return [
    /**
     * 🔴→✅ Modèles pointés vers `App\Models\Role`/`App\Models\Permission`
     * (ajoutés au même ticket que ce correctif) plutôt que les classes
     * Spatie par défaut — `roles.id`/`permissions.id` sont des UUID
     * (migration `2026_01_15_000001_create_permission_tables.php`),
     * seuls ces modèles personnalisés portent `HasUuids` pour générer
     * réellement cette valeur à la création.
     */
    'models' => [
        'permission' => App\Models\Permission::class,
        'role' => App\Models\Role::class,
    ],

    'table_names' => [
        'roles' => 'roles',
        'permissions' => 'permissions',
        'model_has_permissions' => 'model_has_permissions',
        'model_has_roles' => 'model_has_roles',
        'role_has_permissions' => 'role_has_permissions',
    ],

    'column_names' => [
        // AgriERP : users.id est UUID (voir docblock migration users) —
        // model_morph_key doit correspondre à la colonne générée par
        // uuidMorphs('model') dans la migration permission_tables.
        'role_pivot_key' => 'role_id',
        'permission_pivot_key' => 'permission_id',
        'model_morph_key' => 'model_id',
        'team_foreign_key' => 'team_id',
    ],

    'register_permission_check_method' => true,
    'register_octane_reset_listener' => false,
    'events_enabled' => false,
    'teams' => false,
    'use_passport_client_credentials' => false,
    'display_permission_in_exception' => false,
    'display_role_in_exception' => false,
    'enable_wildcard_permission' => false,

    'cache' => [
        'expiration_time' => \DateInterval::createFromDateString('24 hours'),
        'key' => 'spatie.permission.cache',
        'store' => 'default',
    ],
];
