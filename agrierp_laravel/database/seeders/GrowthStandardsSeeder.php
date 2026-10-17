<?php

namespace Database\Seeders;

use App\Models\GrowthStandard;
use Illuminate\Database\Seeder;

/**
 * Ticket 14.9 (Sprint 14) — objectifs de GMQ repris des valeurs RÉELLES
 * d'`analyse-croissance.html` (tableau `GMQ_DATA`), jamais inventées :
 *   Cuniculture engraissement      15-20 g/j
 *   Aviculture engraissement (chair) 45-55 g/j
 *   Aviculture croissance (poussins) 20-30 g/j
 *   Porciculture croissance        500-650 g/j
 *   Porciculture reproduction (truies) 40-80 g/j
 *
 * ⚠️ HÉLICICULTURE ABSENTE, SIGNALÉE : le prototype ne propose aucun objectif
 * de croissance pour les escargots (son filtre d'espèce n'en propose que 3).
 * Aucun barème n'est inventé — les lots d'héliciculture apparaîtront avec un
 * GMQ réel et un statut « Objectif non défini », plutôt qu'un objectif fictif.
 */
class GrowthStandardsSeeder extends Seeder
{
    public function run(): void
    {
        $standards = [
            ['species_code' => 'cuniculture',  'stage_label' => 'engraissement', 'gmq_min_g_per_day' => 15,  'gmq_max_g_per_day' => 20],
            ['species_code' => 'cuniculture',  'stage_label' => 'croissance',    'gmq_min_g_per_day' => 15,  'gmq_max_g_per_day' => 20],
            ['species_code' => 'aviculture',   'stage_label' => 'engraissement', 'gmq_min_g_per_day' => 45,  'gmq_max_g_per_day' => 55],
            ['species_code' => 'aviculture',   'stage_label' => 'croissance',    'gmq_min_g_per_day' => 20,  'gmq_max_g_per_day' => 30],
            ['species_code' => 'porciculture', 'stage_label' => 'croissance',    'gmq_min_g_per_day' => 500, 'gmq_max_g_per_day' => 650],
            ['species_code' => 'porciculture', 'stage_label' => 'engraissement', 'gmq_min_g_per_day' => 500, 'gmq_max_g_per_day' => 650],
            ['species_code' => 'porciculture', 'stage_label' => 'reproduction',  'gmq_min_g_per_day' => 40,  'gmq_max_g_per_day' => 80],
        ];

        foreach ($standards as $s) {
            GrowthStandard::firstOrCreate(
                ['species_code' => $s['species_code'], 'stage_label' => $s['stage_label']],
                $s
            );
        }
    }
}
