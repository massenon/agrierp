<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\Role;
use App\Models\Permission;

class RolesAndPermissionsSeeder extends Seeder
{
    public function run(): void
    {
        // Exactement 4 roles - Document 01 Section 3.3, jamais 5
        $roles = ['admin', 'comptable', 'caissier', 'animalier'];
        foreach ($roles as $role) {
            Role::firstOrCreate(['name' => $role]);
        }

        $permissions = [
            'view-elevage', 'manage-elevage', 'archive-elevage', 'export-elevage',
            'view-ventes', 'manage-ventes', 'export-ventes',
            'view-achats', 'manage-achats',
            'view-stocks', 'manage-stocks',
            // 🔴→✅ TICKET 14.64 — `manage-facturation` MANQUAIT. Le module
            // n'avait qu'une permission de LECTURE : il etait donc impossible
            // d'exprimer « peut modifier la facturation », alors que l'ecran
            // ecrit. Meme situation pour les parametres ci-dessous.
            'view-facturation', 'manage-facturation',
            'view-rh', 'manage-rh',
            'view-administration', 'manage-administration',
            'view-comptabilite', 'manage-comptabilite', 'close-fiscal-year',
            // ⚠️ `manage-parametres` etait utilise NEUF FOIS dans le code
            // (Restauration, Reinitialisation, Sauvegardes, Roles...) sans
            // jamais etre cree ici. Aucun role ne le portait, il n'existe
            // aucun contournement admin (`Gate::before`) : ces ecrans etaient
            // donc inaccessibles A TOUT LE MONDE en base reelle. Les tests
            // passaient parce qu'ils creaient la permission eux-memes.
            'view-parametres', 'manage-parametres',
            'manage-users', 'manage-modules',
            'view-rapports', 'export-rapports',
        ];
        foreach ($permissions as $perm) {
            Permission::firstOrCreate(['name' => $perm]);
        }

        Role::findByName('admin')->givePermissionTo(Permission::all());

        Role::findByName('comptable')->givePermissionTo([
            'view-comptabilite', 'manage-comptabilite', 'close-fiscal-year',
            'view-rapports', 'export-rapports',
        ]);

        Role::findByName('caissier')->givePermissionTo([
            'view-ventes', 'manage-ventes', 'export-ventes',
        ]);

        Role::findByName('animalier')->givePermissionTo([
            'view-elevage', 'manage-elevage', 'archive-elevage', 'export-elevage',
        ]);
    }
}
