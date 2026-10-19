<?php

namespace App\Livewire\Shared;

use App\Services\DemandeSynchronisationService;
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

    /**
     * Ticket S-T6 — « Demander la synchronisation des postes » : dépose une demande que chaque poste connecté lit dans
     * les 30 secondes, puis synchronise. `$poste` nul : tous les postes ; sinon le seul poste nommé (nom de son jeton,
     * qui doit figurer dans la liste affichée).
     *
     * ⚠️ Le serveur n'envoie toujours rien lui-même (décision du Sprint 0) : il DEMANDE, et c'est le poste qui tire et
     * envoie. Un poste hors ligne ne lira la demande qu'à son retour, si elle est encore valide.
     */
    public function demander(?string $poste = null): void
    {
        $this->authorize('manage-users');

        if ($poste !== null && ! $this->postes->contains(fn ($ligne) => $ligne['poste'] === $poste)) {
            $this->dispatch('toast', message: 'Poste inconnu du serveur : demande non envoyée.', type: 'error');

            return;
        }

        app(DemandeSynchronisationService::class)->demander($poste, auth()->user());

        $this->dispatch('toast', message: $poste === null
            ? 'Demande envoyée : les postes connectés synchroniseront dans les 30 secondes.'
            : "Demande envoyée au poste {$poste} : il synchronisera dans les 30 secondes s'il est connecté.",
            type: 'success');
    }

    public function render()
    {
        return view('livewire.shared.etat-synchronisation-postes');
    }
}
