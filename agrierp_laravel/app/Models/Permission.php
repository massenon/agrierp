<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Spatie\Permission\Models\Permission as SpatiePermission;

/**
 * 🔴→✅ Même correction que `App\Models\Role` (voir son docblock pour le
 * diagnostic complet) — `permissions.id` est également UUID côté
 * migration, sans `HasUuids` côté modèle jusqu'à ce ticket.
 *
 * Ticket S-T7 — la matrice des droits s'écrit aussi DEPUIS la permission (`$permission->assignRole($role)`) : les
 * rôles gagnés ou perdus sont datés, comme dans `App\Models\Role`.
 */
class Permission extends SpatiePermission
{
    use HasUuids;

    public function assignRole(...$roles): static
    {
        $avant = $this->idsDesRoles();
        parent::assignRole(...$roles);
        $this->daterLesRoles($avant);

        return $this;
    }

    public function removeRole(...$role): static
    {
        $avant = $this->idsDesRoles();
        parent::removeRole(...$role);
        $this->daterLesRoles($avant);

        return $this;
    }

    public function syncRoles(...$roles): static
    {
        $avant = $this->idsDesRoles();
        parent::syncRoles(...$roles);
        $this->daterLesRoles($avant);

        return $this;
    }

    /** @return array<int, string> */
    private function idsDesRoles(): array
    {
        return $this->exists ? $this->roles()->pluck('roles.id')->map(fn ($id) => (string) $id)->all() : [];
    }

    /** Date les rôles touchés : ceux qui avaient la permission avant, et ceux qui l'ont après. */
    private function daterLesRoles(array $avant): void
    {
        $touches = array_unique([...$avant, ...$this->idsDesRoles()]);
        if ($touches !== []) {
            Role::query()->whereIn('id', $touches)->update(['updated_at' => now()]);
        }
    }
}
