<?php

namespace Database\Seeders;

use App\Models\CostCenter;
use App\Models\LivestockSpecies;
use Illuminate\Database\Seeder;

/**
 * Ticket 10.7 (Sprint 10) — 5 centres de coûts de type "filière"
 * (Cuniculture, Aviculture, Porciculture, Maraîchage, Transformation),
 * absents de tout seeder jusqu'ici bien que `cost_centers` existe depuis
 * le ticket 10.1. `parent_species_id` relié aux vraies espèces déjà
 * seedées (`LivestockSpeciesSeeder`) quand une correspondance existe —
 * Maraîchage et Transformation n'ont pas d'espèce animale associée,
 * `parent_species_id` reste nul pour ces deux-là (filières non liées à
 * l'élevage), jamais une correspondance inventée.
 */
class CostCentersSeeder extends Seeder
{
    public function run(): void
    {
        $filieres = [
            'Cuniculture' => 'cuniculture',
            'Aviculture' => 'aviculture',
            'Porciculture' => 'porciculture',
            'Maraîchage' => null,
            'Transformation' => null,
        ];

        foreach ($filieres as $label => $speciesCode) {
            $speciesId = $speciesCode ? LivestockSpecies::where('code', $speciesCode)->first()?->id : null;

            CostCenter::firstOrCreate(
                ['label' => $label, 'type' => 'filiere'],
                ['parent_species_id' => $speciesId, 'is_active' => true]
            );
        }

        // Ticket DEP6 (DEP-Q1) — le centre par défaut des dépenses sans centre (poste ancien, reprise de l'existant).
        CostCenter::general();
    }
}
