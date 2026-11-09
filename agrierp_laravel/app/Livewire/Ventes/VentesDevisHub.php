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

    /**
     * CONF-4 (DV-20) — « Enregistrer Vente » (la caisse) n'est montée qu'aux comptes `manage-ventes` : le comptable (LECTURE
     * des ventes, `view-ventes`) ouvre le hub sur l'historique et ne voit pas cet onglet. Corrigé à chaque rendu : l'onglet
     * peut venir de l'URL (`?tab=vente`) ou d'un `$set` forgé.
     */
    public function render()
    {
        $peutEncaisser = \Illuminate\Support\Facades\Gate::allows('manage-ventes');

        if (! $peutEncaisser && $this->tab === 'vente') {
            $this->tab = 'historique';
        }

        return view('livewire.ventes.ventes-devis-hub', ['peutEncaisser' => $peutEncaisser, 'title' => 'Ventes & Devis']);
    }
}
