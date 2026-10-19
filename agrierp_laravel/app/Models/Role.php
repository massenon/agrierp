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
 *
 * Ticket S-T7 (méthode TATACORA, piège « table de liaison ») — LA MATRICE DES DROITS DATE LE RÔLE. Les droits d'un
 * rôle vivent dans `role_has_permissions`, une table de liaison sans horodatage : Spatie l'écrit sans toucher
 * `roles.updated_at`. Un tirage au curseur `updated_at` ne verrait donc jamais qu'un rôle a gagné ou perdu un droit,
 * et le poste appliquerait l'ancienne matrice sans rien dire. Aujourd'hui le tirage sert `roles` EN ENTIER à chaque
 * fois (`SyncController::pull`), ce qui masque le piège ; le tirage paginé et filtré prévu (S-T4) le rouvrirait. Toute
 * écriture de la matrice par le rôle date donc le rôle ([touch]) ; par la permission, voir `App\Models\Permission`.
 */
class Role extends SpatieRole
{
    use HasUuids;

    public function givePermissionTo(...$permissions): static
    {
        parent::givePermissionTo(...$permissions);
        $this->dater();

        return $this;
    }

    public function syncPermissions(...$permissions): static
    {
        parent::syncPermissions(...$permissions);
        $this->dater();

        return $this;
    }

    public function revokePermissionTo($permission): static
    {
        parent::revokePermissionTo($permission);
        $this->dater();

        return $this;
    }

    /** Un rôle pas encore enregistré n'a rien à dater : sa création le datera. */
    private function dater(): void
    {
        if ($this->exists) {
            $this->touch();
        }
    }
}
