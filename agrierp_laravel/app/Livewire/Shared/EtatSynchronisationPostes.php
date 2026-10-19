<?php

namespace App\Livewire\Shared;

use App\Services\JournalSynchronisationService;
use Illuminate\Support\Facades\Gate;
use Livewire\Component;

/**
 * Ticket H3 — bouton « Synchroniser » de la barre supérieure et modale « Synchronisation » du WEB
 * (PRD `docs/prd/synchronisation-barre-superieure.md`, EF1, EF2, EF11).
 *
 * ⚠️ Ce bouton n'envoie rien : le serveur EST la base (décision du Sprint 0, README_SPRINT0 §0.2 — un bouton qui
 * ferait semblant serait un décor). Il ouvre l'ÉTAT DES POSTES : dernier contact, dernier envoi, refus. Réservé
 * à l'administrateur (`manage-users`, comme « Vider les sessions », ticket 15.54) : la liste nomme les comptes.
 */
class EtatSynchronisationPostes extends Component
{
    public function mount(): void
    {
        abort_unless(Gate::allows('manage-users'), 403);
    }

    public function getPostesProperty()
    {
        return app(JournalSynchronisationService::class)->etatDesPostes();
    }

    public function actualiser(): void
    {
        $this->authorize('manage-users');
        unset($this->postes);
    }

    public function render()
    {
        return view('livewire.shared.etat-synchronisation-postes');
    }
}
