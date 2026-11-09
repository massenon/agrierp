<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Spatie\Permission\PermissionRegistrar;

/**
 * Ticket CONF-5 (DV-06) — le CAISSIER consulte et réimprime ses factures, pour les bases DÉJÀ DÉPLOYÉES.
 *
 * ⚠️ UNE MIGRATION, PAS SEULEMENT LE SEEDER : `RolesAndPermissionsSeeder` ne rejoue pas en production. Sans elle, le menu
 * montrait « Facturation » au caissier alors que la route `/facturation` (`can:view-facturation`) lui répondait 403.
 *
 * - crée `view-facturation` si elle manque (jamais redondant : `firstOrCreate`) ;
 * - l'attribue au rôle `caissier` en LECTURE seule : `manage-facturation`, `correct-invoices` et la retransmission restent
 *   refusés ;
 * - N'ENLÈVE RIEN À PERSONNE (`givePermissionTo` n'ajoute que ce qui manque : rejouée, elle ne change rien) ; un rôle
 *   absent (base neuve, le seeder passera ensuite) est ignoré sans erreur ; les autres rôles ne sont pas touchés.
 */
return new class extends Migration
{
    private const DROIT = 'view-facturation';

    public function up(): void
    {
        app()[PermissionRegistrar::class]->forgetCachedPermissions();

        Permission::firstOrCreate(['name' => self::DROIT, 'guard_name' => 'web']);

        Role::where('name', 'caissier')->where('guard_name', 'web')->first()?->givePermissionTo(self::DROIT);

        app()[PermissionRegistrar::class]->forgetCachedPermissions();
    }

    /** Retire la seule lecture ajoutée au caissier ; le droit lui-même existait avant (admin, comptable). */
    public function down(): void
    {
        app()[PermissionRegistrar::class]->forgetCachedPermissions();

        Role::where('name', 'caissier')->where('guard_name', 'web')->first()?->revokePermissionTo(self::DROIT);

        app()[PermissionRegistrar::class]->forgetCachedPermissions();
    }
};
