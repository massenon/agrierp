<?php

namespace App\Livewire\PublicPages;

use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 14.15 (Sprint 14) — welcome.html -> Livewire\PublicPages\Welcome
 * Page d'accueil publique, avant authentification.
 *
 * Reutilise `layouts.guest` (ticket 1.1) plutot qu'un 3e layout : ce layout
 * fournit deja la coquille HTML, Vite et la preference de theme, et rien dans
 * ces pages publiques n'exige autre chose. Le fond degrade du prototype,
 * porte par son <body>, est applique sur le conteneur racine de la vue —
 * rendu identique sans dupliquer un layout pour une seule regle CSS.
 *
 * ⚠️ ECRAN STATIQUE, AUCUNE DONNEE : composant Livewire uniquement pour
 * respecter la convention de routage du projet (une route pointe une classe
 * de composant), meme precedent que `Aide\Index` (ticket 1.5, page statique).
 */
#[Layout('layouts.guest')]
class Welcome extends Component
{
    public function render()
    {
        return view('public.welcome', ['title' => 'Bienvenue']);
    }
}
