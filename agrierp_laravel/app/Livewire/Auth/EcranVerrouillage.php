<?php

namespace App\Livewire\Auth;

use App\Services\VerrouSessionService;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Sprint VW (VW2) — page `/verrouillage` : l'écran de verrouillage atteint quand une page est demandée session
 * verrouillée (rechargement, nouvel onglet, lien direct). Même contenu que la surcouche (`x-verrou-session`), mais en
 * page entière : l'application n'est pas dans la page, rien ne peut donc être « retiré » dans les outils du navigateur.
 *
 * ⚠️ Aucune action Livewire ici : la saisie du mot de passe part en `fetch` vers `POST /deverrouiller` (ou, sans
 * JavaScript, par le formulaire HTML). Un envoi Livewire serait refusé en 423 par `SessionVerrouillee` — c'est
 * justement ce que ce verrou doit faire. Le composant existe pour charger Alpine (fourni par Livewire) et pour suivre
 * la convention des routes plein-page.
 */
#[Layout('layouts.guest')]
class EcranVerrouillage extends Component
{
    public function mount()
    {
        if (! VerrouSessionService::estVerrouillee()) {
            return $this->redirect(route('dashboard.index'), navigate: false);
        }
    }

    public function render()
    {
        $utilisateur = Auth::user();

        return view('livewire.auth.ecran-verrouillage', [
            'nom' => $utilisateur->name,
            'identifiant' => $utilisateur->username ?: $utilisateur->email,
            'minutes' => $utilisateur->delaiVerrouillage(),
            'title' => 'Application verrouillée',
        ]);
    }
}
