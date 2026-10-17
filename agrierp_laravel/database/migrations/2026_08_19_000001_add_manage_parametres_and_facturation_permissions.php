<?php

use Illuminate\Database\Migrations\Migration;
use App\Models\Permission;
use App\Models\Role;

/**
 * Ticket 14.64 (Sprint 14) — DEUX PERMISSIONS UTILISÉES MAIS JAMAIS CRÉÉES.
 *
 * 🔴 `manage-parametres` était appelé **neuf fois** dans le code (Restauration,
 * Réinitialisation, Sauvegardes, Rôles & Permissions…) sans figurer dans le
 * seeder. Aucun rôle ne la portait, et le projet n'a **aucun contournement
 * admin** (`Gate::before`) : `$this->authorize('manage-parametres')` refusait
 * donc **tout le monde, administrateur compris**. Ces écrans étaient
 * inaccessibles en base réelle — vérifié : `$admin->can('manage-parametres')`
 * renvoyait `false`.
 *
 * ⚠️ **LES TESTS PASSAIENT PARCE QU'ILS CRÉAIENT LA PERMISSION EUX-MÊMES**
 * (`Permission::findOrCreate('manage-parametres')` en `setUp`). Ils validaient
 * une situation qui n'existait que dans la base de test.
 *
 * 🔴 `manage-facturation` n'existait pas non plus : le module n'avait qu'une
 * permission de LECTURE, alors que son écran écrit. Il était donc impossible
 * d'exprimer « peut modifier la facturation ».
 *
 * ⚠️ **UNE MIGRATION, PAS SEULEMENT LE SEEDER** : les bases déjà déployées ne
 * rejouent pas le seeder. Corriger uniquement le seeder laisserait les
 * installations existantes cassées.
 */
return new class extends Migration
{
    private const PERMISSIONS = ['manage-parametres', 'manage-facturation'];

    public function up(): void
    {
        app()[\Spatie\Permission\PermissionRegistrar::class]->forgetCachedPermissions();

        foreach (self::PERMISSIONS as $nom) {
            Permission::firstOrCreate(['name' => $nom, 'guard_name' => 'web']);
        }

        // ⚠️ L'ADMINISTRATEUR REÇOIT TOUT, comme le fait le seeder
        // (`Role::findByName('admin')->givePermissionTo(Permission::all())`).
        // Sans cela la migration créerait les permissions sans les attribuer,
        // et les écrans resteraient inaccessibles.
        $admin = Role::where('name', 'admin')->where('guard_name', 'web')->first();
        $admin?->givePermissionTo(self::PERMISSIONS);

        app()[\Spatie\Permission\PermissionRegistrar::class]->forgetCachedPermissions();
    }

    public function down(): void
    {
        app()[\Spatie\Permission\PermissionRegistrar::class]->forgetCachedPermissions();

        Permission::whereIn('name', self::PERMISSIONS)->delete();

        app()[\Spatie\Permission\PermissionRegistrar::class]->forgetCachedPermissions();
    }
};
