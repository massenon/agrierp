{{--
    Ticket EX7 (EF8, PRD § 7) — « Exercice 2027 ▾ » : chaque exercice avec son badge « Ouvert » (vert), « Provisoire »
    (ambre : ouvert, à-nouveaux calculés) ou « Clôturé » (gris, cadenas). Le poste reprend ces libellés mot pour mot
    (`agrierp_flutter/lib/core/widgets/selecteur_exercice.dart`, vérifié par `test/selecteur_exercice_test.dart`).
--}}
@php
    $badges = [
        'ouvert' => 'bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30',
        'provisoire' => 'bg-accent-yellow/20 text-brand-forest border-accent-yellow',
        'cloture' => 'bg-surface-zebra text-outline border-outline-variant',
    ];
@endphp
<div x-data="{ open: false }" class="relative" @click.outside="open = false">
    <button type="button" dusk="selecteur-exercice" @click="open = !open" title="Exercice affiché" class="flex items-center gap-xs text-brand-forest font-semibold text-xs border border-outline-variant rounded-full px-sm py-1 hover:bg-surface-zebra">
        <span class="material-symbols-outlined text-[16px]">calendar_month</span><span>Exercice {{ $annee }}</span><span class="material-symbols-outlined text-[16px]">expand_more</span>
    </button>
    <div x-show="open" x-cloak class="absolute right-0 mt-sm w-60 bg-white border border-outline-variant rounded-lg shadow-lg z-50 overflow-hidden">
        <p class="px-md py-sm border-b border-outline-variant font-bold text-xs text-brand-forest">Exercice affiché</p>
        @forelse($exercices as $exercice)
            <button type="button" wire:key="exercice-{{ $exercice['annee'] }}" wire:click="choisir({{ $exercice['annee'] }})" class="w-full flex items-center justify-between gap-xs px-md py-sm text-xs hover:bg-surface-zebra {{ $exercice['choisi'] ? 'font-bold text-brand-emerald' : 'text-on-surface' }}">
                <span>Exercice {{ $exercice['annee'] }}</span>
                <span class="inline-flex items-center gap-[2px] px-sm py-[2px] rounded-full text-[10px] font-bold border {{ $badges[$exercice['statut']] }}">@if($exercice['statut'] === 'cloture')<span class="material-symbols-outlined text-[12px]">lock</span>@endif{{ $exercice['libelle'] }}</span>
            </button>
        @empty
            <p class="text-[11px] text-outline text-center py-md px-md">Aucun exercice comptable n'est encore ouvert.</p>
        @endforelse
    </div>
</div>
