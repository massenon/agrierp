<?php

namespace App\Livewire\Auth;

use App\Actions\ChangerMotDePasseAction;
use App\Support\PolitiqueMotDePasse;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\ValidationException;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket MDP-1 — PAGE DE CHANGEMENT DE MOT DE PASSE OBLIGATOIRE (`/changer-mot-de-passe`).
 *
 * Un administrateur a posé un mot de passe TEMPORAIRE (`users.must_change_password`) : tant que le titulaire n'en a pas
 * choisi un à lui, `ChangementMotDePasseObligatoire` (middleware du groupe `web`) refuse tout le reste. Même formulaire
 * et mêmes règles que « Mon Profil » (`PolitiqueMotDePasse`), même point de passage (`ChangerMotDePasseAction`), mêmes
 * textes que l'écran du poste. Mise en page `guest` : aucun menu, rien d'autre que ce formulaire et « Se déconnecter ».
 *
 * ⚠️ Pas d'`authorize()` : le geste porte sur le compte de celui qui est connecté (comme `MonProfil::updatePassword`).
 */
#[Layout('layouts.guest')]
class ChangementMotDePasseObligatoire extends Component
{
    public string $current_password = '';

    public string $new_password = '';

    public string $new_password_confirmation = '';

    public function mount()
    {
        if (! Auth::user()?->must_change_password) {
            return $this->redirect(route('dashboard.index'), navigate: false);
        }
    }

    public function updatePassword()
    {
        $this->validate([
            'current_password' => ['required', 'current_password'],
            'new_password' => [...PolitiqueMotDePasse::regles(), 'confirmed'],
        ], [
            'current_password.required' => 'Le mot de passe temporaire est obligatoire.',
            'current_password.current_password' => "Le mot de passe temporaire ne correspond pas à celui donné par l'administrateur.",
            ...PolitiqueMotDePasse::messages(),
            'new_password.confirmed' => 'La confirmation ne correspond pas au mot de passe saisi.',
        ]);

        try {
            app(ChangerMotDePasseAction::class)->executer(Auth::user(), $this->new_password);
        } catch (ValidationException $e) {
            $this->addError('new_password', $e->validator->errors()->first());

            return;
        }

        session()->flash('toast', ['message' => 'Mot de passe mis à jour avec succès.', 'type' => 'success']);

        return $this->redirect(route('dashboard.index'), navigate: false);
    }

    public function render()
    {
        return view('livewire.auth.changement-mot-de-passe-obligatoire', ['title' => 'Changement de mot de passe']);
    }
}
