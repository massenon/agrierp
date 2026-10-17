@props([
    'name',
    'itemLabel' => null,
    'action' => null,
])
<x-modal :name="$name" max-width="sm">
    <div class="text-center">
        <div class="w-12 h-12 bg-error-bg rounded-full flex items-center justify-center mx-auto mb-md">
            <span class="material-symbols-outlined text-error-deep text-[28px]">warning</span>
        </div>
        <h3 class="font-bold text-lg text-brand-forest mb-xs">Confirmer la Suppression ?</h3>
        <p class="text-xs text-outline mb-md">
            Vous êtes sur le point de supprimer le paramètre
            @if($itemLabel)<strong class="text-error-deep">{{ $itemLabel }}</strong>@else ce paramètre @endif.
        </p>
        <div class="bg-error-bg/50 border border-error-deep/20 rounded-lg p-sm text-[11px] text-error-deep text-left mb-lg flex items-start gap-xs">
            <span class="material-symbols-outlined text-[16px] flex-shrink-0 mt-0.5">info</span>
            <span>Attention : Cette action est irréversible et retirera ce paramètre du calcul automatique des fiches d'élevage.</span>
        </div>
        <div class="flex justify-center gap-sm">
            <button type="button" x-on:click="$dispatch('close-modal', { name: '{{ $name }}' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
            @if($action)
                <button type="button" wire:click="{{ $action }}" class="px-md py-sm rounded-lg bg-error-deep text-white text-sm font-bold hover:bg-red-800">Oui, Supprimer définitivement</button>
            @endif
        </div>
    </div>
</x-modal>
