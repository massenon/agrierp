<?php

namespace App\Livewire\Elevage\Concerns;

use App\Models\LivestockDailyEntry;
use App\Services\EffectifParCategorieService;

/**
 * 🔴→✅ RATIONNEMENT AUTOMATIQUE — fiches Lapins et Porcs.
 *
 * Tant que la bande n'a pas d'effectif de départ par catégorie, les trois champs « Effectif de départ »
 * sont PRÉ-REMPLIS depuis le stade de la bande (`EffectifParCategorieService::departDepuisStade`) : les
 * effectifs par catégorie, la provende servie et l'autonomie alimentaire se calculent dès l'ouverture de
 * la fiche, sans saisie. Le départ est enregistré avec la première fiche, comme un départ saisi, puis
 * verrouillé ; il reste corrigeable avant ce premier enregistrement (bande mixte).
 *
 * Exige du composant : `bande` (propriété calculée), `selectedDate`, `departRepro`, `departSevre`, `departJeune`.
 */
trait AvecDepartAutomatique
{
    protected function preremplirDepartDepuisStade(): void
    {
        $bande = $this->bande;

        if (! $bande || app(EffectifParCategorieService::class)->teteDeChaine($bande->id) !== null) {
            return;
        }

        // Effectif au DÉBUT du jour choisi, calculé ici : la propriété calculée peut porter la date précédente.
        $debutJour = (new LivestockDailyEntry(['lot_id' => $bande->id, 'entry_date' => $this->selectedDate]))->previousEffectif();
        $depart = EffectifParCategorieService::departDepuisStade($bande->loadMissing('species'), $debutJour);

        if ($depart !== null) {
            $this->departRepro = $depart['repro'];
            $this->departSevre = $depart['sevre'];
            $this->departJeune = $depart['jeune'];
        }
    }
}
