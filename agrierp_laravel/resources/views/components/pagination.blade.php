{{--
    Ticket EX7 (EF9) — LE pied de pagination partagé (il n'en existait aucun : `CLAUDE.md`). Il reçoit le paginateur
    d'une liste paginée dans l'exercice affiché (`ExerciceChoisi::PAR_PAGE` lignes par page) et pilote la page par les
    méthodes de `Livewire\WithPagination` (`previousPage`, `nextPage`), au nom de page de la liste — plusieurs listes
    sur un même écran (Soins & Vaccins) ou un même hub ne se marchent pas dessus.
    Le poste reprend ces libellés mot pour mot (`agrierp_flutter/lib/core/widgets/pagination_agri.dart`).

    Ticket E2 — extension : prop optionnelle `$perPage` (int|null, défaut null).
    - Sans `$perPage` (EX7) : « X lignes dans l'exercice YYYY — page N sur M ».
    - Avec `$perPage` (E2) : « X–Y sur Z résultats » + sélecteur « Par page : [10] [25] » +
      flèches. Le composant Livewire exposant `$perPage` doit implémenter `changerParPage(int $n)`.
    La poste porte cette extension dans `pagination_agri.dart`.
--}}
@props(['paginator', 'perPage' => null])
@php
    $total = $paginator->total();
    $nomPage = $paginator->getPageName();
@endphp
<div {{ $attributes->class(['flex flex-wrap items-center justify-between gap-sm px-md py-sm border-t border-outline-variant bg-white']) }} data-pagination>
    @if($perPage !== null)
        {{-- E2 : « X–Y sur Z résultats » + sélecteur 10/25 --}}
        @php
            $debut = $total > 0 ? ($paginator->currentPage() - 1) * $perPage + 1 : 0;
            $fin = min($debut + $perPage - 1, $total);
        @endphp
        <p class="text-[11px] text-outline">{{ $total > 0 ? $debut.'–'.$fin.' sur '.$total.' résultats' : 'Aucun résultat' }}</p>
        <div class="flex items-center gap-xs">
            <span class="text-[11px] text-outline">Par page :</span>
            @foreach([10, 25] as $n)
                <button type="button" wire:click="changerParPage({{ $n }})" class="text-xs font-bold px-sm py-1 rounded-lg border {{ $n === $perPage ? 'bg-brand-forest text-white border-brand-forest' : 'border-outline-variant text-brand-forest hover:bg-surface-zebra' }}">{{ $n }}</button>
            @endforeach
            @if($paginator->hasPages())
                <button type="button" wire:click="previousPage('{{ $nomPage }}')" @disabled($paginator->onFirstPage()) class="flex items-center gap-[2px] text-xs font-bold px-sm py-1 rounded-lg border border-outline-variant text-brand-forest hover:bg-surface-zebra disabled:opacity-50"><span class="material-symbols-outlined text-[16px]">chevron_left</span>Précédent</button>
                <button type="button" wire:click="nextPage('{{ $nomPage }}')" @disabled(! $paginator->hasMorePages()) class="flex items-center gap-[2px] text-xs font-bold px-sm py-1 rounded-lg border border-outline-variant text-brand-forest hover:bg-surface-zebra disabled:opacity-50">Suivant<span class="material-symbols-outlined text-[16px]">chevron_right</span></button>
            @endif
        </div>
    @else
        {{-- EX7 : « X lignes dans l'exercice YYYY — page N sur M » --}}
        <p class="text-[11px] text-outline">{{ $total }} {{ $total > 1 ? 'lignes' : 'ligne' }} dans l'exercice {{ \App\Support\ExerciceChoisi::annee() }} — page {{ $paginator->currentPage() }} sur {{ $paginator->lastPage() }}</p>
        @if($paginator->hasPages())
            <div class="flex items-center gap-xs">
                <button type="button" wire:click="previousPage('{{ $nomPage }}')" @disabled($paginator->onFirstPage()) class="flex items-center gap-[2px] text-xs font-bold px-sm py-1 rounded-lg border border-outline-variant text-brand-forest hover:bg-surface-zebra disabled:opacity-50"><span class="material-symbols-outlined text-[16px]">chevron_left</span>Précédent</button>
                <button type="button" wire:click="nextPage('{{ $nomPage }}')" @disabled(! $paginator->hasMorePages()) class="flex items-center gap-[2px] text-xs font-bold px-sm py-1 rounded-lg border border-outline-variant text-brand-forest hover:bg-surface-zebra disabled:opacity-50">Suivant<span class="material-symbols-outlined text-[16px]">chevron_right</span></button>
            </div>
        @endif
    @endif
</div>
