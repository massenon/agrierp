<?php

namespace App\Livewire\Shared;

use App\Services\RappelsDuJourService;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;
use Livewire\Component;

/**
 * Ticket POP1 — fenêtre « Rappels du jour », montée une fois dans `layouts/app.blade.php` pour qui voit Soins et vaccins.
 *
 * ⚠️ QUAND ELLE S'OUVRE (PRD § 5, EF3) — la décision est prise ICI, côté serveur, donc testée :
 *  - le navigateur ne fait que transmettre ce qu'il sait : `$dejaVuSession` (marqueur de `sessionStorage`, une session de
 *    navigateur) et `$masqueLe` (date « Ne plus afficher aujourd'hui » de `localStorage`, pour cet utilisateur) ;
 *  - une CONNEXION (événement `Login`, `AppServiceProvider`) pose `rappels_forcer` : la fenêtre se rouvre même dans une
 *    session de navigateur déjà vue ; le drapeau est consommé par la première ouverture ;
 *  - « Ne plus afficher aujourd'hui » l'emporte sur tout, connexion comprise (c'est une demande explicite de l'utilisateur) ;
 *  - AUCUN rappel ⇒ aucune fenêtre (jamais une fenêtre vide) ;
 *  - une erreur de calcul est journalisée et reste silencieuse : jamais un écran rouge, jamais un chargement bloqué.
 */
class RappelsDuJour extends Component
{
    public bool $visible = false;

    /** @var array<int, array<string, mixed>> */
    public array $rappels = [];

    /** Une connexion vient d'avoir lieu : le navigateur doit interroger le serveur même s'il a déjà vu la fenêtre. */
    public bool $forcer = false;

    public int $joursRappel = 3;

    public function mount(): void
    {
        $this->forcer = (bool) session('rappels_forcer', false);
    }

    /** @return bool vrai si la fenêtre s'ouvre */
    public function ouvrir(bool $dejaVuSession, ?string $masqueLe): bool
    {
        $this->visible = false;
        $this->rappels = [];

        try {
            $utilisateur = Auth::user();
            if (! $utilisateur) {
                return false;
            }

            $forcer = (bool) session()->pull('rappels_forcer', false);

            if ($masqueLe === today()->toDateString()) {
                return false;
            }
            if ($dejaVuSession && ! $forcer) {
                return false;
            }

            // Le droit `view-elevage` est contrôlé par le service (un seul endroit) : sans lui, la liste est vide.
            $rappels = app(RappelsDuJourService::class)->pourUtilisateur($utilisateur);
            if ($rappels === []) {
                return false;
            }

            $this->rappels = $rappels;
            $this->joursRappel = app(\App\Services\AlertesElevageService::class)->joursRappelSoins();
            $this->visible = true;

            return true;
        } catch (\Throwable $e) {
            Log::warning('Rappels du jour : calcul impossible.', ['exception' => $e->getMessage()]);
            $this->visible = false;
            $this->rappels = [];

            return false;
        }
    }

    public function fermer(): void
    {
        $this->visible = false;
    }

    public function render()
    {
        return view('livewire.shared.rappels-du-jour');
    }
}
