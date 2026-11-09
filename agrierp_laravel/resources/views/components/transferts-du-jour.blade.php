@props(['transferts'])
{{-- Ticket 15.46 — transferts entre bandes du jour affiché (écran Transferts entre Bandes). Hors maquette, assumé :
     rien n'est affiché les jours sans transfert, la fiche reste celle du prototype. Compris dans l'effectif final. --}}
@if(($transferts['transfert_entree'] ?? 0) > 0 || ($transferts['transfert_sortie'] ?? 0) > 0)
    <div class="bg-surface-zebra border border-outline-variant rounded-lg p-sm text-xs text-brand-forest flex items-center gap-xs" role="status">
        <span class="material-symbols-outlined text-[16px] text-brand-emerald">swap_horiz</span>
        <span>
            Transferts entre bandes ce jour :
            @if(($transferts['transfert_entree'] ?? 0) > 0)<strong>+{{ $transferts['transfert_entree'] }}</strong> entré(s)@endif
            @if(($transferts['transfert_entree'] ?? 0) > 0 && ($transferts['transfert_sortie'] ?? 0) > 0) ; @endif
            @if(($transferts['transfert_sortie'] ?? 0) > 0)<strong>−{{ $transferts['transfert_sortie'] }}</strong> sorti(s)@endif
            — compris dans l'effectif final. Ils se modifient depuis l'écran
            <a wire:navigate href="/transferts-bandes" class="font-bold underline">Transferts entre Bandes</a>.
        </span>
    </div>
@endif
