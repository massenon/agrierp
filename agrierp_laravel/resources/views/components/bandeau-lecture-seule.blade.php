{{--
    Tickets EX7 (EF10) + EX8 (EF12), fusion — LE bandeau de lecture seule d'un exercice clos, un seul composant :
     - en haut du contenu, pour l'exercice AFFICHÉ (`livewire/shared/bandeau-exercice.blade.php`, « Passer à 2027 »
       choisit l'exercice de saisie) ;
     - en tête du formulaire d'une fiche d'élevage, pour l'exercice du JOUR CHOISI (`Concerns\AvecMoisDeFiche`,
       « Passer à 2027 » ramène la fiche au jour de saisie).
    `$bandeau` : `ExerciceChoisi::bandeau()` / `bandeauDe()` (`texte`, `cible`) ; rien quand il vaut `null`. `$action` :
    la méthode Livewire du lien « Passer à … ».
    ⚠️ Le poste reprend ce bandeau mot pour mot (`BandeauLectureSeule`, `agrierp_flutter/lib/core/widgets/bandeau_exercice.dart`).
    ⚠️ Pas de `data-lecture-seule` ici : cet attribut grise (`app.css`, `@lectureSeule`) — un bandeau n'est pas un bouton.
--}}
@props(['bandeau' => null, 'action' => 'passer'])
@if($bandeau)
    <div {{ $attributes->merge(['class' => 'bg-surface-zebra border border-outline-variant rounded-lg p-sm flex flex-wrap items-center gap-sm']) }} data-bandeau-exercice>
        <span class="material-symbols-outlined text-outline text-[20px]">lock</span>
        <p class="text-xs font-bold text-on-surface flex-1">{{ $bandeau['texte'] }}</p>
        @if($bandeau['cible'])
            <button type="button" wire:click="{{ $action }}" class="text-xs font-bold text-brand-emerald underline hover:text-brand-forest">Passer à {{ $bandeau['cible'] }}</button>
        @endif
    </div>
@endif
