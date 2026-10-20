{{--
    Ticket EX7 (EF10, PRD § 7) — bandeau de lecture seule d'un exercice clos, en haut du contenu. Le poste reprend ce
    texte mot pour mot (`agrierp_flutter/lib/core/widgets/bandeau_exercice.dart`).
--}}
<div>
    @if($bandeau)
        <div class="bg-surface-zebra border border-outline-variant rounded-lg p-sm mb-lg flex flex-wrap items-center gap-sm" data-bandeau-exercice>
            <span class="material-symbols-outlined text-outline text-[20px]">lock</span>
            <p class="text-xs font-bold text-on-surface flex-1">{{ $bandeau['texte'] }}</p>
            @if($bandeau['cible'])
                <button type="button" wire:click="passer" class="text-xs font-bold text-brand-emerald underline hover:text-brand-forest">Passer à {{ $bandeau['cible'] }}</button>
            @endif
        </div>
    @endif
</div>
