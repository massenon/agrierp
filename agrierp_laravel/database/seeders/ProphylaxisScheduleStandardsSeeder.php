<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Repris exactement de `PROPHYLAXIE_STORE` (parametres-elevage.html,
 * source de vérité n°1) — ticket 2.8.
 *
 * ⚠️ `cycle_day_start`/`cycle_day_end` ajoutés (gap trouvé en construisant
 * `DailyProphylaxyReminderJob`, `RAPPEL_DE_PROPHYLAXIE_DU_JOUR.md`) —
 * dérivés du `period_label` existant, jamais une seconde source de
 * vérité. Les 2 entrées "Le 1er du mois" (cuniculture, porciculture)
 * restent volontairement à `null` : leur base de calcul est le jour
 * calendaire du mois, pas le jour du cycle depuis la mise en lot —
 * mécanisme différent, non couvert ici, documenté honnêtement plutôt que
 * forcé dans un modèle qui ne lui correspond pas.
 */
class ProphylaxisScheduleStandardsSeeder extends Seeder
{
    public function run(): void
    {
        $schedule = [
            'cuniculture' => [
                ['period_label' => 'Le 1er du mois', 'cycle_day_start' => null, 'cycle_day_end' => null, 'treatment' => 'Déparasitage', 'product_recommended' => 'Levalap', 'dosage' => "1C / 5L d'eau", 'withdrawal_days' => 7],
                ['period_label' => 'Le 2 au 4e jour', 'cycle_day_start' => 2, 'cycle_day_end' => 4, 'treatment' => 'Anti-stress', 'product_recommended' => 'Vitalyte / Alfacéryl', 'dosage' => "1C / 10L d'eau", 'withdrawal_days' => 0],
                ['period_label' => 'Le 5e jour', 'cycle_day_start' => 5, 'cycle_day_end' => 5, 'treatment' => 'Anti-coccidien', 'product_recommended' => 'Antcox / Trysulmisine', 'dosage' => "1C / 20L d'eau", 'withdrawal_days' => 5],
                ['period_label' => 'Le 9e jour', 'cycle_day_start' => 9, 'cycle_day_end' => 9, 'treatment' => 'Hépato-protection', 'product_recommended' => 'Hépaturyl', 'dosage' => "1C / 5L d'eau", 'withdrawal_days' => 0],
                ['period_label' => 'Le 15e jour', 'cycle_day_start' => 15, 'cycle_day_end' => 15, 'treatment' => 'Vitamines', 'product_recommended' => "Amin'Total", 'dosage' => "1C / 20L d'eau", 'withdrawal_days' => 0],
            ],
            'aviculture' => [
                ['period_label' => 'J1 (au couvoir)', 'cycle_day_start' => 1, 'cycle_day_end' => 1, 'treatment' => 'Vaccination Marek', 'product_recommended' => 'Vaccin bivalent Marek', 'dosage' => 's.c au couvoir', 'withdrawal_days' => 0],
                ['period_label' => 'J2', 'cycle_day_start' => 2, 'cycle_day_end' => 2, 'treatment' => 'Fortifiant Démarrage', 'product_recommended' => 'Sucre / Solution glucose', 'dosage' => '6M / 1L eau', 'withdrawal_days' => 0],
                ['period_label' => 'J3', 'cycle_day_start' => 3, 'cycle_day_end' => 3, 'treatment' => 'Vaccination Newcastle', 'product_recommended' => 'HB1 + Alfacéryl', 'dosage' => '1C / 10L eau', 'withdrawal_days' => 0],
                ['period_label' => 'J4', 'cycle_day_start' => 4, 'cycle_day_end' => 4, 'treatment' => 'Vaccination Bronchite', 'product_recommended' => 'Vaccin vivant Bronchite', 'dosage' => '1C / 10L eau', 'withdrawal_days' => 0],
                ['period_label' => 'J5', 'cycle_day_start' => 5, 'cycle_day_end' => 5, 'treatment' => 'Anti-coccidien', 'product_recommended' => 'Superhypracox', 'dosage' => '1C / 5L eau', 'withdrawal_days' => 5],
                ['period_label' => 'J7', 'cycle_day_start' => 7, 'cycle_day_end' => 7, 'treatment' => 'Vaccination Gumboro', 'product_recommended' => 'Gumboro + Alfacéryl', 'dosage' => '1C / 10L eau', 'withdrawal_days' => 0],
                ['period_label' => 'J14', 'cycle_day_start' => 14, 'cycle_day_end' => 14, 'treatment' => 'Rappel Newcastle', 'product_recommended' => 'Newcastle + Tétracolivit', 'dosage' => '1C / 10L eau', 'withdrawal_days' => 7],
            ],
            'porciculture' => [
                ['period_label' => 'Le 1er du mois', 'cycle_day_start' => null, 'cycle_day_end' => null, 'treatment' => 'Déparasitage Général', 'product_recommended' => 'Ivermectine', 'dosage' => '1ml / 33kg', 'withdrawal_days' => 14],
                ['period_label' => 'Le 4e jour', 'cycle_day_start' => 4, 'cycle_day_end' => 4, 'treatment' => 'Traitement Vermifuge', 'product_recommended' => 'Ivermectine', 'dosage' => '1ml / 33kg', 'withdrawal_days' => 14],
                ['period_label' => 'Le 10e jour', 'cycle_day_start' => 10, 'cycle_day_end' => 10, 'treatment' => 'Hépato-protection', 'product_recommended' => 'Hépaturyl', 'dosage' => "1ml / L d'eau", 'withdrawal_days' => 0],
                ['period_label' => 'Le 21e jour', 'cycle_day_start' => 21, 'cycle_day_end' => 21, 'treatment' => 'Contrôle Sanitaire & Vaccin', 'product_recommended' => 'Vaccin Variole / Erysipèle', 'dosage' => '0.5ml / sujet', 'withdrawal_days' => 21],
            ],
        ];

        foreach ($schedule as $speciesCode => $entries) {
            foreach ($entries as $entry) {
                DB::table('prophylaxis_schedule_standards')->insert([
                    'id' => (string) Str::uuid(),
                    'species_code' => $speciesCode,
                    'period_label' => $entry['period_label'],
                    'cycle_day_start' => $entry['cycle_day_start'],
                    'cycle_day_end' => $entry['cycle_day_end'],
                    'treatment' => $entry['treatment'],
                    'product_recommended' => $entry['product_recommended'],
                    'dosage' => $entry['dosage'],
                    'withdrawal_days' => $entry['withdrawal_days'],
                    'is_active' => true,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }
        }
    }
}
