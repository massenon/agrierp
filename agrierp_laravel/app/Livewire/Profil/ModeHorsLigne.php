<?php

namespace App\Livewire\Profil;

use Illuminate\Support\Facades\Gate;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * PWA-1 (décision du client, 08/11/2026) — « Activer le mode hors ligne » : appairage de CE navigateur comme un POSTE.
 *
 * ⚠️ Ce composant ne porte AUCUN état et ne reçoit JAMAIS le mot de passe : le formulaire est géré par le JavaScript de la
 * page (`resources/js/hors-ligne/activation-page.js`), qui appelle le `POST /api/auth/login` du poste (jeton Sanctum nommé
 * `pwa-<uuid>`, gardé chiffré dans le navigateur — voir `docs`/CLAUDE.md « PWA »). Aucune route serveur nouvelle pour la
 * synchronisation : c'est le protocole des postes (`/api/sync/pull|push`).
 *
 * Réservé aux comptes qui encaissent (`manage-ventes`) OU tiennent les fiches d'élevage (`manage-elevage`) : Gate unique `utiliser-mode-hors-ligne` (CAISSE-1, volet animalier). L'écran de la PWA suit ensuite les droits du compte.
 */
#[Layout('layouts.app')]
class ModeHorsLigne extends Component
{
    public function mount(): void
    {
        abort_unless(Gate::allows('utiliser-mode-hors-ligne'), 403);
    }

    public function render()
    {
        return view('livewire.profil.mode-hors-ligne', [
            'identifiant' => auth()->user()->username ?: auth()->user()->email,
        ]);
    }
}
