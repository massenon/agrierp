@props([
    'name' => 'confirm-hard-delete',
    'itemLabel' => null,
    'action' => null,
    'warning' => null,
    // Ticket CFG-1 — titre et bouton propres au geste (« Révoquer l'appairage ») ; défauts inchangés.
    'title' => 'Suppression définitive',
    'confirmLabel' => 'Supprimer Définitivement',
])
<x-modal :name="$name" max-width="sm">
    <div class="text-center">
        <span class="material-symbols-outlined text-error-deep" style="font-size:44px;">warning</span>
        <h3 class="font-bold text-lg text-error-deep mt-sm">{{ $title }}</h3>
        <p class="text-sm text-outline mt-xs">
            @if($itemLabel)
                <strong>{{ $itemLabel }}</strong> sera supprimé(e) définitivement.
            @else
                Cet enregistrement sera supprimé définitivement.
            @endif
            Cette action est irréversible.
        </p>
        @if($warning)
            <p class="text-xs text-error-deep bg-error-bg border border-error-deep/20 rounded-lg p-sm mt-sm">{{ $warning }}</p>
        @endif
        <div class="flex justify-center gap-sm mt-lg">
            <button type="button" x-on:click="$dispatch('close-modal', { name: '{{ $name }}' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
            @if($action)
                <button type="button" wire:click="{{ $action }}" x-on:click="$dispatch('close-modal', { name: '{{ $name }}' })" class="px-md py-sm rounded-lg bg-error-red text-white text-sm font-bold hover:bg-red-700">{{ $confirmLabel }}</button>
            @endif
        </div>
    </div>
</x-modal>
