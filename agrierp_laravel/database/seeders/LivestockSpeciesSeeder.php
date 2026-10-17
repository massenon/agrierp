<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class LivestockSpeciesSeeder extends Seeder
{
    public function run(): void
    {
        $species = [
            ['code' => 'cuniculture', 'label' => 'Cuniculture (Lapins)', 'is_enabled' => true, 'icon' => 'cruelty_free'],
            ['code' => 'aviculture', 'label' => 'Aviculture (Volailles)', 'is_enabled' => true, 'icon' => 'egg'],
            ['code' => 'porciculture', 'label' => 'Porciculture (Porcs)', 'is_enabled' => true, 'icon' => 'pets'],
            ['code' => 'helico', 'label' => 'Héliciculture (Escargots)', 'is_enabled' => false, 'icon' => 'bug_report'],
        ];

        foreach ($species as $s) {
            DB::table('livestock_species')->insert([
                'id' => (string) Str::uuid(),
                'code' => $s['code'],
                'label' => $s['label'],
                'is_enabled' => $s['is_enabled'],
                'icon' => $s['icon'],
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }
}
