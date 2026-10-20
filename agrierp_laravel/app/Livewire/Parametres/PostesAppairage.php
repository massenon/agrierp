<?php

namespace App\Livewire\Parametres;

use App\Models\AuditLog;
use App\Services\DemandeSynchronisationService;
use App\Services\JournalSynchronisationService;
use Illuminate\Support\Facades\Gate;
use Laravel\Sanctum\PersonalAccessToken;
use Livewire\Component;

/**
 * Ticket CFG-1 (décision client du 19/10/2026) — onglet « Postes & Appairage » du hub Paramètres.
 *
 * Un POSTE APPAIRÉ est un jeton Sanctum nommé d'après le poste (`personal_access_tokens.name` = identifiant tiré par
 * le poste, `device_name` de `POST /api/auth/login`). La liste est celle de la modale « Synchronisation » de la barre
 * supérieure (ticket H3, `JournalSynchronisationService::etatDesPostes`, avec le dernier contrôle de cohérence S-T6) :
 * la même requête, jamais une seconde qui finirait par diverger.
 *
 * ⚠️⚠️ « RÉVOQUER L'APPAIRAGE » SUPPRIME TOUS LES JETONS DE CE POSTE, quel que soit le compte qui s'y est connecté.
 * Avec S-T2 (le `device_id` envoyé doit être le nom du jeton), le poste ne peut plus ni tirer ni envoyer : sa
 * synchronisation reçoit 401 et s'arrête (S-T1) jusqu'à une nouvelle connexion, qui exige le mot de passe d'un compte
 * actif. Ses saisies en attente restent sur le poste : rien n'est perdu, rien ne part tant qu'il n'est pas réappairé.
 *
 * Réservé à l'administrateur (`manage-users`, comme la modale H3 : la liste nomme les comptes).
 */
class PostesAppairage extends Component
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

    /** Ticket S-T6 — même demande que la modale H3 : tous les postes (`null`) ou le seul poste nommé. */
    public function demander(?string $poste = null): void
    {
        $this->authorize('manage-users');

        if ($poste !== null && ! $this->posteConnu($poste)) {
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
     * Révoque l'appairage du poste nommé : supprime ses jetons (tous comptes confondus), puis l'audite.
     *
     * ⚠️ Le poste doit figurer dans la liste affichée : un nom forgé dans la requête ne supprime rien.
     */
    public function revoquer(string $poste): void
    {
        $this->authorize('manage-users');

        if (! $this->posteConnu($poste)) {
            $this->dispatch('toast', message: 'Poste inconnu du serveur : aucun appairage révoqué.', type: 'error');

            return;
        }

        $supprimes = PersonalAccessToken::query()->where('name', $poste)->delete();

        AuditLog::record('sync.appairage_revoque', 'sync');
        unset($this->postes);

        $this->dispatch('toast',
            message: "Appairage du poste {$poste} révoqué ({$supprimes} jeton".($supprimes > 1 ? 's' : '').' supprimé'.($supprimes > 1 ? 's' : '')
                .") : il ne synchronisera plus jusqu'à une nouvelle connexion.",
            type: 'success');
    }

    private function posteConnu(string $poste): bool
    {
        return $this->postes->contains(fn ($ligne) => $ligne['poste'] === $poste);
    }

    public function render()
    {
        return view('livewire.parametres.postes-appairage');
    }
}
