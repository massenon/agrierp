<?php

namespace App\Livewire\Shared;

use App\Support\ExerciceChoisi;
use Livewire\Component;

/**
 * Ticket EX7 (EF10, PRD § 7) — bandeau « Exercice 2026 clôturé — lecture seule. Les saisies se font dans l'exercice
 * 2027. » en haut du contenu, avec le lien « Passer à 2027 », tant que l'exercice affiché est clos.
 *
 * ⚠️ Confort seulement : la garantie reste le refus du serveur (EX5) — voir `ExerciceChoisi`.
 */
class BandeauExercice extends Component
{
    public function passer()
    {
        $cible = ExerciceChoisi::bandeau()['cible'] ?? null;

        if ($cible === null || ! ExerciceChoisi::choisir($cible)) {
            return null;
        }

        $origine = (string) request()->header('Referer', '');

        return $this->redirect($origine !== '' && str_starts_with($origine, url('/')) ? $origine : url('/dashboard'));
    }

    public function render()
    {
        return view('livewire.shared.bandeau-exercice', ['bandeau' => ExerciceChoisi::bandeau()]);
    }
}
