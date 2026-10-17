<?php

namespace App\Livewire\Achats;

use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 5.2 (Sprint 5) — achats-commandes.html → Livewire\Achats\AchatsCommandesHub
 * Hub à 3 onglets (le prototype charge 3 iframes — enregistrer-achat.html,
 * liste-achats.html, bons-commande.html — converties en composition,
 * même traitement que les hubs précédents).
 *
 * Seul l'onglet "Enregistrer un Achat" est réel dans ce ticket. Liste
 * d'Achats (5.4) et Bons de Commande (ticket 5.5, PDF officiel) ont
 * chacun leurs propres tickets et affichent un bandeau d'attente jusque-là.
 */
#[Layout('layouts.app')]
class AchatsCommandesHub extends Component
{
    #[Url]
    public string $tab = 'enregistrer';

    public function render()
    {
        return view('livewire.achats.achats-commandes-hub', ['title' => 'Achats & Commandes']);
    }
}
