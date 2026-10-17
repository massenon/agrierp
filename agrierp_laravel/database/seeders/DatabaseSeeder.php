<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

/**
 * Portée Sprint 0 uniquement (ticket 0.3). Les seeders des sprints suivants
 * (LivestockSpeciesSeeder, ChartOfAccountsSeeder, FeedRationStandardsSeeder,
 * TreasuryAccountsSeeder, ProductsSeeder, DemoDataSeeder — voir SEEDER_TEST.md
 * §3-8) seront ajoutés à la liste `$this->call([...])` au fil de l'eau,
 * chacun à son propre ticket de sprint (Sprint 2 pour la majorité), jamais
 * en avance sur les migrations dont ils dépendent — un appel vers une
 * classe/table qui n'existe pas encore casserait
 * `php artisan migrate:fresh --seed` (Document 00 §2.2, zéro placeholder).
 */
class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $this->call([
            RolesAndPermissionsSeeder::class,
            DemoUsersSeeder::class,
            NotificationsSeeder::class,
            LivestockSpeciesSeeder::class,
            ModulesConfigSeeder::class,
            ProductsSeeder::class,
            ChartOfAccountsSeeder::class,
            FiscalYearSeeder::class,
            TreasuryAccountsSeeder::class,
            FeedRationStandardsSeeder::class,
            ProphylaxisScheduleStandardsSeeder::class,
            FeedTypesSeeder::class,
            CostCentersSeeder::class,
            IncomeTaxBracketsSeeder::class,   // ticket 14.38 — bareme ITS
            FixedAssetsSeeder::class,   // ticket 14.26

            // Sprint 2+ : DemoDataSeeder::class,
        ]);
    }
}
