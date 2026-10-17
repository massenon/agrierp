<?php

namespace App\Livewire\Achats;

use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 5.6 (Sprint 5) — fournisseurs.html → Livewire\Achats\FournisseursHub
 * Hub à 3 onglets (le prototype charge 3 iframes — ajouter-fournisseur.html,
 * fiches-fournisseurs.html, dettes-fournisseurs.html — converties en
 * composition, même traitement que les hubs précédents).
 *
 * "Ajouter Fournisseur" (CRUD complet, canonique) et "Fiches
 * Fournisseurs" (vue analytique réelle) sont réels dans ce ticket.
 * "Dettes Fournisseurs" a son propre ticket dédié (5.7) et affiche un
 * bandeau d'attente jusque-là.
 */
#[Layout('layouts.app')]
class FournisseursHub extends Component
{
    #[Url]
    public string $tab = 'ajouter';

    public function render()
    {
        return view('livewire.achats.fournisseurs-hub', ['title' => 'Fournisseurs']);
    }
}
