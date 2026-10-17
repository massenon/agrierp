<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Repris exactement de `PROVENDE_STORE` (parametres-elevage.html, source
 * de vérité n°1) — ticket 2.8.
 */
class FeedTypesSeeder extends Seeder
{
    public function run(): void
    {
        $speciesIds = DB::table('livestock_species')->pluck('id', 'code');

        $feeds = [
            ['name' => 'Aliment Démarrage (Poussin)', 'species' => 'aviculture', 'bag_kg' => 25, 'price_kg' => 300],
            ['name' => 'Aliment Croissance (Poulette)', 'species' => 'aviculture', 'bag_kg' => 25, 'price_kg' => 280],
            ['name' => 'Aliment Ponte (Pondeuse)', 'species' => 'aviculture', 'bag_kg' => 25, 'price_kg' => 260],
            ['name' => 'Aliment Lapins Reproducteur / Mère', 'species' => 'cuniculture', 'bag_kg' => 25, 'price_kg' => 290],
            ['name' => 'Aliment Porcelet / Démarrage', 'species' => 'porciculture', 'bag_kg' => 25, 'price_kg' => 320],
        ];

        foreach ($feeds as $f) {
            DB::table('feed_types')->insert([
                'id' => (string) Str::uuid(),
                'name' => $f['name'],
                'species_id' => $speciesIds[$f['species']] ?? null,
                'standard_bag_weight_kg' => $f['bag_kg'],
                'price_per_kg' => $f['price_kg'],
                'is_active' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }
}
