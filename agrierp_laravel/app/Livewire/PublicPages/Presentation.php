<?php

namespace App\Livewire\PublicPages;

use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 14.15 (Sprint 14) — landing-page.html -> Livewire\PublicPages\Presentation
 * Page de presentation publique (modules, apercu, architecture).
 *
 * Nommee `Presentation` et routee sur `/presentation` plutot que
 * `/landing-page` : l'URL est publique et visible, un anglicisme technique
 * n'a pas sa place dans une application dont toute l'interface est en
 * francais. Le fichier source du prototype garde son nom, la correspondance
 * est documentee ici.
 */
#[Layout('layouts.guest')]
class Presentation extends Component
{
    public function render()
    {
        return view('public.presentation', ['title' => 'Presentation']);
    }
}
