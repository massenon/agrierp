<?php

namespace App\Livewire\RH;

use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 8.2 (Sprint 8) — personnel-stages.html → Livewire\RH\PersonnelStagesHub
 * Hub à 5 onglets (le prototype charge 5 iframes — registre-employes.html,
 * registre-stagiaires.html, feuille-pointage.html, gestion-paie.html,
 * rh-attestations.html — converties en composition, même traitement que
 * les hubs précédents).
 *
 * Seul l'onglet "Registre Employés" est réel dans ce ticket. Les 4 autres
 * ont chacun leurs propres tickets et affichent un bandeau d'attente
 * jusque-là.
 */
#[Layout('layouts.app')]
class PersonnelStagesHub extends Component
{
    #[Url]
    public string $tab = 'employes';

    public function render()
    {
        return view('livewire.rh.personnel-stages-hub', ['title' => 'Personnel & Stages']);
    }
}
