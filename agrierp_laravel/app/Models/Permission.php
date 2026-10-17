<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Spatie\Permission\Models\Permission as SpatiePermission;

/**
 * 🔴→✅ Même correction que `App\Models\Role` (voir son docblock pour le
 * diagnostic complet) — `permissions.id` est également UUID côté
 * migration, sans `HasUuids` côté modèle jusqu'à ce ticket.
 */
class Permission extends SpatiePermission
{
    use HasUuids;
}
