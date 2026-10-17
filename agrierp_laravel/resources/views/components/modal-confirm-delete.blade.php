@props([
    'name' => 'confirm-archive',
    'itemLabel' => null,       // nom de l'élément concerné, affiché pour éviter toute ambiguïté
    'action' => null,          // méthode Livewire à appeler à la confirmation (ex. "archive")
])
<x-modal :name="$name" max-width="sm">
    <div class="text-center">
        <span class="material-symbols-outlined text-error-deep text-[44px]">archive</span>
        <h3 class="font-bold text-lg text-on-surface mt-sm">Confirmer l'archivage</h3>
        <p class="text-sm text-outline mt-xs">
            @if($itemLabel)
                <strong>{{ $itemLabel }}</strong> sera marqué(e) comme archivé(e) (statut inactif).
            @else
                L'enregistrement sera marqué comme archivé (statut inactif).
            @endif
            Aucune suppression définitive n'est effectuée.
        </p>
        <div class="flex justify-center gap-sm mt-lg">
            <button type="button" x-on:click="$dispatch('close-modal', { name: '{{ $name }}' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
            @if($action)
                <button type="button" wire:click="{{ $action }}" x-on:click="$dispatch('close-modal', { name: '{{ $name }}' })" class="px-md py-sm rounded-lg bg-error-red text-white text-sm font-bold hover:bg-red-700">Archiver</button>
            @endif
        </div>
    </div>
</x-modal>
