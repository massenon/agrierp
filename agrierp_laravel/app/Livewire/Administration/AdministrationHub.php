<?php

namespace App\Livewire\Administration;

use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 9.1 (Sprint 9) — administration.html → Livewire\Administration\AdministrationHub
 * RÉSOUT LE GAP HISTORIQUE CRITIQUE : "Administration module class
 * referenced in routes and sidebar but never built" (ultra-review).
 *
 * Hub à 3 onglets (le prototype charge 3 iframes — gestion-courriers.html,
 * archivage-documents.html, documents-administratifs.html — converties
 * en composition, même traitement que les autres hubs). Les 3 onglets
 * sont réels dès ce ticket — aucune raison de laisser ce module
 * historiquement absent à moitié construit.
 */
#[Layout('layouts.app')]
class AdministrationHub extends Component
{
    #[Url]
    public string $tab = 'courriers';

    public function render()
    {
        return view('livewire.administration.administration-hub', ['title' => 'Administration & Documents']);
    }
}
