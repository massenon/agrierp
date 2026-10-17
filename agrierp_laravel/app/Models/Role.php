<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Spatie\Permission\Models\Role as SpatieRole;

/**
 * 🔴→✅ GAP RÉEL TROUVÉ AU PREMIER `migrate:fresh --seed` CONTRE UN VRAI
 * MySQL LOCAL — jamais visible en simple vérification `php -l` ni dans
 * ce bac à sable sans MySQL réel.
 *
 * `2026_01_15_000001_create_permission_tables.php` crée `roles.id` en
 * UUID (cohérence avec `users.id`, décision documentée ticket 0.1),
 * mais le seeder utilisait `Spatie\Permission\Models\Role` directement
 * — sans `HasUuids`, Eloquent ne génère aucune valeur pour `id` avant
 * l'insertion, et la colonne UUID n'a pas de `DEFAULT` côté MySQL :
 * "Field 'id' doesn't have a default value". Ce modèle comble
 * l'écart — jamais recréé de zéro, hérite de `Spatie\Permission\Models\Role`
 * pour garder 100% du comportement Spatie (relations, cache,
 * `findByName()`...), ajoute uniquement `HasUuids`.
 */
class Role extends SpatieRole
{
    use HasUuids;
}
