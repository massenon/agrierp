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
            // CONF-4 (DV-20) — droit FIN du comptable : créer un avoir et retransmettre une facture au MeCeF, SANS ouvrir la caisse.
            // Avant, l'avoir et l'annulation passaient par `manage-ventes`, le même droit que l'encaissement : le donner au
            // comptable lui aurait ouvert le POS. L'annulation d'une vente et la caisse restent à `manage-ventes` SEUL.
            'correct-invoices',
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
            // CONF-4 (DV-20) — LECTURE des ventes, achats et stocks ; consulter la facturation ; corriger par avoir.
            // Jamais `manage-ventes` (caisse, annulation), `manage-achats`, `manage-stocks`, `manage-elevage`, `manage-users`,
            // `manage-parametres` ni `manage-facturation` (conversion de devis en facture).
            'view-ventes', 'view-achats', 'view-stocks',
            'view-facturation', 'correct-invoices',
        ]);

        Role::findByName('caissier')->givePermissionTo([
            'view-ventes', 'manage-ventes', 'export-ventes',
            // CONF-5 (DV-06) — le caissier CONSULTE et RÉIMPRIME ses factures : `view-facturation` seul. Jamais
            // `manage-facturation` (conversion de devis), `correct-invoices` (avoir fiscal) ni la retransmission.
            'view-facturation',
        ]);

        Role::findByName('animalier')->givePermissionTo([
            'view-elevage', 'manage-elevage', 'archive-elevage', 'export-elevage',
        ]);
    }
}
