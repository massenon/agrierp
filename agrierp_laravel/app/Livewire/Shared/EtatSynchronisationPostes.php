<?php

namespace App\Livewire\Shared;

use App\Services\DemandeSynchronisationService;
use App\Services\JournalSynchronisationService;
use App\Services\ResynchronisationPostesService;
use Illuminate\Support\Facades\Gate;
use Livewire\Component;

/**
 * Ticket H3 — bouton « Synchroniser » de la barre supérieure et modale « Synchronisation » du WEB
 * (PRD `docs/prd/synchronisation-barre-superieure.md`, EF1, EF2, EF11).
 *
 * ⚠️ Ce bouton ne fait pas semblant (décision du Sprint 0, README_SPRINT0 §0.2 — un bouton décor). Il ouvre l'ÉTAT DES
 * POSTES : dernier contact, dernier envoi, refus, et — correction du client du 21/10/2026 (ticket SW-1) — ce que
 * chaque poste n'a pas encore REÇU du site, avec « Renvoyer vers ce poste » : le web fait aussi revenir les données
 * vers les postes. Réservé à l'administrateur (`manage-users`, comme « Vider les sessions », ticket 15.54) : la liste nomme les comptes.
 */
class EtatSynchronisationPostes extends Component
{
    public function mount(): void
    {
        abort_unless(Gate::allows('manage-users'), 403);
    }

    public function getPostesProperty()
    {
        $retards = app(ResynchronisationPostesService::class);

        // Ticket SW-1 — chaque poste porte aussi ce qu'il n'a pas encore reçu du site (`retard`).
        return app(JournalSynchronisationService::class)->etatDesPostes()
            ->map(fn (array $ligne) => $ligne + ['retard' => $retards->retard($ligne['poste'])]);
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

    /**
     * Ticket SW-1 (correction du client du 21/10/2026) — « Renvoyer vers ce poste » : le web fait AUSSI revenir les
     * données vers les postes. Lève le drapeau « resynchronisation demandée » du poste : à son prochain contact (ping de
     * 30 s ou tirage), il repart d'un tirage COMPLET puis acquitte. Audité (qui, quand, quel poste).
     */
    public function renvoyer(string $poste): void
    {
        $this->authorize('manage-users');

        if (! $this->postes->contains(fn ($ligne) => $ligne['poste'] === $poste)) {
            $this->dispatch('toast', message: 'Poste inconnu du serveur : renvoi non demandé.', type: 'error');

            return;
        }

        app(ResynchronisationPostesService::class)->demanderPoste($poste, auth()->user());
        unset($this->postes);

        $this->dispatch('toast', message: "Renvoi demandé au poste {$poste} : il recevra tout à son prochain contact avec le serveur.", type: 'success');
    }

    /** « Renvoyer vers tous les postes » : même geste, pour chaque poste appairé. */
    public function renvoyerATous(): void
    {
        $this->authorize('manage-users');

        $n = app(ResynchronisationPostesService::class)->demanderTous(auth()->user());
        unset($this->postes);

        $this->dispatch('toast', message: $n === 0
            ? 'Aucun poste appairé : rien à renvoyer.'
            : "Renvoi demandé à {$n} poste(s) : chacun recevra tout à son prochain contact avec le serveur.",
            type: $n === 0 ? 'warning' : 'success');
    }

    public function render()
    {
        return view('livewire.shared.etat-synchronisation-postes');
    }
}
