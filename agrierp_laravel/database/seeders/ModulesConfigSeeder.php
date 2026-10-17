<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Synchronisé avec l'état déjà seedé de `livestock_species.is_enabled`
 * (ticket 2.1) : helico désactivé par défaut, les 3 autres filières
 * activées. Modifiable ensuite depuis Paramètres > Modules Actifs
 * (Sprint 11).
 */
class ModulesConfigSeeder extends Seeder
{
    public function run(): void
    {
        $species = DB::table('livestock_species')->get(['code', 'is_enabled']);

        foreach ($species as $s) {
            DB::table('modules_config')->updateOrInsert(
                ['species_code' => $s->code],
                [
                    'id' => (string) Str::uuid(),
                    'is_enabled' => $s->is_enabled,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]
            );
        }
    }
}
