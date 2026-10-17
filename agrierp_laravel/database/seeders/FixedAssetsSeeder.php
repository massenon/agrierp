<?php

namespace Database\Seeders;

use App\Models\FixedAsset;
use Illuminate\Database\Seeder;

/**
 * Ticket 14.26 (Sprint 14) — immobilisations de départ.
 *
 * Les 3 biens et leurs valeurs viennent de la Note 2 des États Financiers du
 * prototype (`etats-financiers.html`) : Bâtiments et Constructions 2 400 000,
 * Cages Modernes Galvanisées 850 000, Broyeurs et Équipements 620 000.
 * Aucune valeur inventée.
 *
 * ⚠️ SEMÉS EN REPRISE D'ANTÉRIORITÉ (`is_capitalized = false`) : ces biens
 * existaient avant la mise en route de l'ERP. Les capitaliser au semis
 * fabriquerait un décaissement ou une dette qui n'a jamais eu lieu, et les
 * amortir créerait une charge sans l'actif correspondant. L'écran signale
 * explicitement le montant resté hors comptabilité — c'est un état de fait à
 * régulariser par un bilan d'ouverture, pas un défaut à masquer par une
 * écriture inventée.
 *
 * Les durées d'amortissement, elles, ne figurent nulle part dans le prototype
 * et relèvent de l'usage SYSCOHADA courant (bâtiment 20 ans, matériel
 * d'élevage 10 ans, équipement 5 ans) : ce sont des valeurs de départ que le
 * comptable ajuste à l'écran, pas des données reprises d'une maquette.
 */
class FixedAssetsSeeder extends Seeder
{
    public function run(): void
    {
        $biens = [
            ['IMM-BAT-01', 'Bâtiments et constructions d\'élevage', '221', 2_400_000, 20],
            ['IMM-CAG-01', 'Cages modernes galvanisées', '241', 850_000, 10],
            ['IMM-BRO-01', 'Broyeurs et équipements', '244', 620_000, 5],
        ];

        foreach ($biens as [$code, $label, $compte, $valeur, $duree]) {
            FixedAsset::firstOrCreate(
                ['code' => $code],
                [
                    'label' => $label,
                    'account_code' => $compte,
                    'acquisition_date' => now()->startOfYear()->subYear()->format('Y-m-d'),
                    'acquisition_value' => $valeur,
                    'residual_value' => 0,
                    'duration_years' => $duree,
                    'method' => 'lineaire',
                    'status' => 'en_service',
                    'is_capitalized' => false,
                    'is_active' => true,
                ]
            );
        }
    }
}
