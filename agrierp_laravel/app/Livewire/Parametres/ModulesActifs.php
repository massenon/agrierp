<?php

namespace App\Livewire\Parametres;

use App\Models\LivestockSpecies;
use App\Models\ModuleConfig;
use Illuminate\Support\Facades\Auth;
use Livewire\Component;

/**
 * Suite du Sprint 11 — modules-actifs.html → Livewire\Parametres\ModulesActifs
 * "Activez ou désactivez indépendamment chaque espèce d'élevage."
 *
 * Bascule réelle sur `modules_config.is_enabled` — autorité déjà
 * documentée depuis le ticket 3.9 (`ModuleConfig::isEnabled()`, utilisée
 * par `GestionElevage`/`FicheEscargots`) : cet écran est simplement le
 * PREMIER à écrire réellement dans cette table plutôt que de la lire
 * seule. `updated_by` tracé à chaque bascule, cohérent avec le
 * fillable déjà prévu sur `ModuleConfig`.
 *
 * ⚠️ CORRECTION DÉCOUVERTE ET APPLIQUÉE EN CONSTRUISANT CE TICKET : 5
 * composants du projet (`EnregistrerSujets`, `DashboardElevage`,
 * `ParametresElevage`, `GestionBandes`, `AjouterProduit`) filtraient à
 * tort sur `livestock_species.is_enabled` directement plutôt que sur
 * `ModuleConfig::isEnabled()` — la vraie autorité documentée. Corrigés
 * dans ce même ticket via `LivestockSpecies::scopeEnabled()` (nouveau
 * scope centralisant la bonne requête) : sans cette correction, activer
 * ou désactiver un module depuis CET écran n'aurait eu strictement aucun
 * effet sur ces 5 écrans, qui auraient continué à lire l'ancien
 * indicateur non piloté.
 *
 * "La désactivation masque les menus et onglets concernés, sans jamais
 * toucher à la comptabilité générale" (texte du prototype) : reste vrai
 * ici — ce bouton ne touche que `modules_config`, jamais les données
 * déjà enregistrées (lots, ventes...) des espèces concernées, qui
 * réapparaissent dès la réactivation.
 */
class ModulesActifs extends Component
{
    public function getSpeciesProperty()
    {
        return LivestockSpecies::orderBy('label')->get()->map(function ($species) {
            $species->setAttribute('module_enabled', ModuleConfig::isEnabled($species->code));

            return $species;
        });
    }

    public function toggleModule(string $speciesCode): void
    {
        $this->authorize('manage-modules');

        ModuleConfig::definir($speciesCode, ! ModuleConfig::isEnabled($speciesCode), Auth::id());
        $this->dispatch('toast', message: 'Modification appliquée avec succès.', type: 'success');
    }

    public function render()
    {
        return view('livewire.parametres.modules-actifs');
    }
}
