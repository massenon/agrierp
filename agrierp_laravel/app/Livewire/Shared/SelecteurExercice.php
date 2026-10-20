<?php

namespace App\Livewire\Shared;

use App\Support\ExerciceChoisi;
use Livewire\Component;

/**
 * Ticket EX7 (EF8) — sélecteur d'exercice global « Exercice 2027 ▾ » de la barre supérieure, à gauche du bouton
 * « Synchroniser ». Ouvert à tous les rôles : il ne fait que choisir ce qui s'AFFICHE (aucune permission nouvelle,
 * PRD § 3) ; chaque écran garde sa route et ses droits.
 *
 * Le choix est mémorisé en session par `ExerciceChoisi::choisir()`, puis la page est rechargée : chaque écran relit ses
 * bornes, ses listes et ses boutons d'un seul coup (un composant imbriqué ne peut pas faire recalculer les autres).
 */
class SelecteurExercice extends Component
{
    public function choisir(int $annee)
    {
        if (! ExerciceChoisi::choisir($annee)) {
            return null;
        }

        return $this->redirect($this->pageCourante());
    }

    /** La page d'où vient l'appel Livewire (son `Referer`), à défaut le tableau de bord. */
    private function pageCourante(): string
    {
        $origine = (string) request()->header('Referer', '');

        return $origine !== '' && str_starts_with($origine, url('/')) ? $origine : url('/dashboard');
    }

    public function render()
    {
        return view('livewire.shared.selecteur-exercice', [
            'exercices' => ExerciceChoisi::liste(),
            'annee' => ExerciceChoisi::annee(),
        ]);
    }
}
