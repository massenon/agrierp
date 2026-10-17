{{--
    Ticket 15.35 — section « Traitements & Prophylaxie » des fiches Lapins et Porcs.

    Rendu d'un `App\Services\ProtocoleDuJour` (protocole du jour d'une bande,
    issu du barème `prophylaxis_schedule_standards`). Transposition de la
    maquette (fiche-lapins.html, « Moteur automatique de prophylaxie & soins ») et
    du poste Flutter (F0.12). Les directives `wire:` s'adressent au composant
    Livewire de la fiche qui inclut ce fragment (`traitementsCoches`,
    `validerTraitements`).

    ⚠️ Classes Tailwind STATIQUES (tableau de correspondance), jamais concaténées.
--}}
@props(['protocole'])

@php
    $badges = [
        'indetermine' => 'bg-error-bg text-error-deep border border-error-deep/30',
        'libre' => 'bg-surface-zebra text-outline border border-outline-variant',
        'prevus' => 'bg-accent-yellow/30 text-brand-forest border border-accent-yellow',
        'valide' => 'bg-brand-emerald/20 text-brand-emerald border border-brand-emerald',
    ];
    $cle = ! $protocole->determinable() ? 'indetermine'
        : ($protocole->traitements->isEmpty() ? 'libre' : ($protocole->enAttente() === 0 ? 'valide' : 'prevus'));
@endphp

<div class="bg-info-blue/5 border border-info-blue/20 rounded-lg p-md space-y-sm">
    <div class="flex items-center justify-between gap-sm flex-wrap">
        <p class="text-[10px] text-outline">
            @if($protocole->determinable())
                Jour {{ $protocole->jourDeCycle }} du cycle de la bande
            @else
                Jour de cycle inconnu
            @endif
        </p>
        <span class="px-sm py-0.5 rounded-full text-[10px] font-bold {{ $badges[$cle] }}">{{ $protocole->etat() }}</span>
    </div>

    <div class="space-y-xs bg-white border border-outline-variant rounded-lg p-sm">
        @if(! $protocole->determinable())
            <p class="text-xs text-error-deep flex items-start gap-xs">
                <span class="material-symbols-outlined text-[16px] flex-shrink-0">help</span>
                <span>Protocole non calculable — {{ $protocole->motifIndetermine }} Consultez le registre avant toute administration.</span>
            </p>
        @elseif($protocole->traitements->isEmpty())
            <p class="text-xs text-outline italic py-1">— Aucun traitement récurrent programmé pour ce jour —</p>
        @else
            @foreach($protocole->traitements as $ligne)
                @php
                    $standard = $ligne['standard'];
                    $fait = $ligne['deja_administre'];
                    $details = collect([$standard->product_recommended, $standard->dosage])->filter()->implode(' — ');
                @endphp
                <div wire:key="prophy-{{ $standard->id }}" class="flex items-center justify-between text-xs py-1 border-b border-outline-variant/40 last:border-0">
                    <label class="flex items-center gap-xs {{ $fait ? '' : 'cursor-pointer' }}">
                        <input type="checkbox" value="{{ $standard->id }}" wire:model.live="traitementsCoches" @checked($fait) @disabled($fait) class="h-4 w-4 rounded border-outline-variant text-brand-emerald focus:ring-brand-emerald">
                        <span class="font-bold text-brand-forest {{ $fait ? 'line-through' : '' }}">{{ $standard->treatment }}</span>
                        @if($details !== '')
                            <span class="text-outline">({{ $details }})</span>
                        @endif
                    </label>
                    @if($standard->withdrawal_days > 0)
                        <span class="text-[10px] font-bold text-error-deep bg-error-bg px-2 py-0.5 rounded-full">Rémanence {{ $standard->withdrawal_days }}j</span>
                    @endif
                </div>
            @endforeach
        @endif
    </div>

    @if($protocole->calendairesNonEvalues > 0)
        <p class="text-[10px] text-outline">{{ $protocole->calendairesNonEvalues }} entrée(s) du protocole sans jour de cycle (calendaires, ex. « Le 1er du mois ») ne sont pas évaluées ici.</p>
    @endif

    @if($protocole->determinable() && $protocole->enAttente() > 0)
        <div class="space-y-xs">
            <p class="text-[10px] text-error-deep">Valider un traitement rémanent bloque la vente de cette bande jusqu'à la fin du délai d'attente.</p>
            <button type="button" wire:click="validerTraitements" wire:loading.attr="disabled" wire:target="validerTraitements" class="w-full flex items-center justify-center gap-xs px-md py-2 rounded-lg bg-brand-emerald hover:bg-brand-forest text-white text-xs font-bold shadow-sm disabled:opacity-50">
                <span class="material-symbols-outlined text-[16px]">check_circle</span>Valider l'Administration de tous ces Traitements Aujourd'hui
            </button>
        </div>
    @endif

    @if($protocole->determinable() && $protocole->traitements->isNotEmpty())
        <span class="inline-block text-[10px] font-bold px-2 py-0.5 rounded-full {{ $protocole->enAttente() > 0 ? 'text-error-deep bg-error-bg' : 'text-brand-emerald bg-brand-emerald/10' }}">Indice Rouge : {{ $protocole->enAttente() }} soin(s) en attente</span>
    @endif
</div>
