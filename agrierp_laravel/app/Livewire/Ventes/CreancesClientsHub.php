<?php

namespace App\Livewire\Ventes;

use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 4.6 (Sprint 4) — creances-clients.html → Livewire\Ventes\CreancesClientsHub
 * Hub à 4 onglets (le prototype charge 4 iframes — liste-clients.html,
 * suivi-dettes.html, relances-clients.html, historique-avances.html —
 * converties en composition, même traitement que les hubs précédents).
 *
 * Seul l'onglet "Liste des Clients" est réel dans ce ticket. Suivi des
 * Dettes, Relances Clients (ticket 4.7 dédié) et Historique Avances ont
 * chacun leurs propres tickets et affichent un bandeau d'attente jusque-là.
 */
#[Layout('layouts.app')]
class CreancesClientsHub extends Component
{
    #[Url]
    public string $tab = 'liste';

    public function render()
    {
        return view('livewire.ventes.creances-clients-hub', ['title' => 'Créances Clients']);
    }
}
