<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Spatie\Permission\PermissionRegistrar;

/**
 * COMPTA-1 (DV-34, décision du client du 09/11/2026) : le rôle `comptable` reçoit `export-ventes` (PDF de clients, créances, avances, historique des
 * ventes, devis). Le seeder ne rejoue pas sur une base de production : cette migration le fait, IDEMPOTENTE (`givePermissionTo` ne duplique pas), sans
 * toucher aux autres rôles, sans rien retirer ; un rôle `comptable` absent est ignoré. `manage-ventes` (caisse) n'est PAS donné.
 */
return new class extends Migration
{
    private const DROIT = 'export-ventes';

    public function up(): void
    {
        app()[PermissionRegistrar::class]->forgetCachedPermissions();

        $role = Role::where('name', 'comptable')->where('guard_name', 'web')->first();
        if ($role !== null) {
            Permission::firstOrCreate(['name' => self::DROIT, 'guard_name' => 'web']);
            $role->givePermissionTo(self::DROIT);
        }

        app()[PermissionRegistrar::class]->forgetCachedPermissions();
    }

    public function down(): void
    {
        app()[PermissionRegistrar::class]->forgetCachedPermissions();

        Role::where('name', 'comptable')->where('guard_name', 'web')->first()?->revokePermissionTo(self::DROIT);

        app()[PermissionRegistrar::class]->forgetCachedPermissions();
    }
};
