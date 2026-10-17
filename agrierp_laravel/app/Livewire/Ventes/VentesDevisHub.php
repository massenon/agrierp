<?php

namespace App\Livewire\Ventes;

use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 4.2 (Sprint 4) — ventes-devis.html → Livewire\Ventes\VentesDevisHub
 * Hub à 4 onglets (le prototype charge 4 iframes — pos-interface.html,
 * devis.html, historique-ventes.html, retours-avoirs.html — converties en
 * composition, même traitement que les hubs précédents, ex. ticket 2.3).
 *
 * Seul l'onglet "Enregistrer Vente" est réel dans ce ticket
 * (`<livewire:ventes.pos-interface>`, imbriqué — jamais un iframe,
 * Document 06). Les 3 autres (Devis, Historique, Retours) ont leurs
 * propres tickets dédiés (4.3-4.5) et affichent un bandeau d'attente
 * jusque-là.
 */
#[Layout('layouts.app')]
class VentesDevisHub extends Component
{
    #[Url]
    public string $tab = 'vente';

    public function render()
    {
        return view('livewire.ventes.ventes-devis-hub', ['title' => 'Ventes & Devis']);
    }
}
