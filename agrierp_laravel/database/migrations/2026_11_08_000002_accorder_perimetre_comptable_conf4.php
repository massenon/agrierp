<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Spatie\Permission\PermissionRegistrar;

/**
 * Ticket CONF-4 (DV-20, décision du client du 08/11/2026 : « OUI, le même périmètre dans LogiAgriERP ») — PÉRIMÈTRE DU
 * COMPTABLE, pour les bases DÉJÀ DÉPLOYÉES.
 *
 * ⚠️ UNE MIGRATION, PAS SEULEMENT LE SEEDER : `RolesAndPermissionsSeeder` ne rejoue pas en production. Corrigé seul, il
 * laisserait les installations existantes avec l'ancien comptable (comptabilité et rapports seulement).
 *
 * - crée `correct-invoices` (créer un AVOIR, retransmettre une facture au MeCeF) si elle manque : elle sépare la
 *   correction comptable de la CAISSE, que l'avoir et l'annulation partageaient avec l'encaissement (`manage-ventes`) ;
 * - l'attribue à `admin` et à `comptable` ;
 * - donne en plus au comptable les droits de LECTURE déjà existants : `view-ventes`, `view-achats`, `view-stocks`,
 *   `view-facturation` ;
 * - N'ENLÈVE RIEN À PERSONNE (`givePermissionTo` n'ajoute que ce qui manque : rejouée, elle ne change rien) ; un rôle
 *   absent (base neuve, le seeder passera ensuite) est ignoré sans erreur ; `caissier` et `animalier` ne sont pas touchés.
 */
return new class extends Migration
{
    /** Nouveau droit fin de CONF-4. */
    private const NOUVEAU = 'correct-invoices';

    /** Ce que le comptable reçoit (miroir de `RolesAndPermissionsSeeder`). */
    private const COMPTABLE = ['view-ventes', 'view-achats', 'view-stocks', 'view-facturation', self::NOUVEAU];

    public function up(): void
    {
        app()[PermissionRegistrar::class]->forgetCachedPermissions();

        foreach (self::COMPTABLE as $nom) {
            Permission::firstOrCreate(['name' => $nom, 'guard_name' => 'web']);
        }

        Role::where('name', 'admin')->where('guard_name', 'web')->first()?->givePermissionTo(self::COMPTABLE);
        Role::where('name', 'comptable')->where('guard_name', 'web')->first()?->givePermissionTo(self::COMPTABLE);

        app()[PermissionRegistrar::class]->forgetCachedPermissions();
    }

    /**
     * Retire le seul droit créé par CONF-4 (et les lectures que la migration a ajoutées au comptable). Les lectures
     * `view-*` des autres rôles restent : elles existaient avant ce ticket.
     */
    public function down(): void
    {
        app()[PermissionRegistrar::class]->forgetCachedPermissions();

        Role::where('name', 'comptable')->where('guard_name', 'web')->first()?->revokePermissionTo(self::COMPTABLE);
        Permission::where('name', self::NOUVEAU)->delete();

        app()[PermissionRegistrar::class]->forgetCachedPermissions();
    }
};
