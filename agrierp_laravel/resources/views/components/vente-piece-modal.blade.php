@props([
    'name' => 'vente-piece',
    'qtyModel',                 // nom de la propriété Livewire liée à la quantité — DOIT valoir 1 par défaut côté composant
    'amountModel',               // nom de la propriété Livewire liée au montant global (FCFA)
    'productNameProperty' => null, // nom de la propriété Livewire portant le nom du produit sélectionné
    'confirmAction' => 'confirmVentePiece', // méthode Livewire appelée à la confirmation
    'qtyLabel' => 'Nombre de sujets / Quantité',
])
<x-modal :name="$name" max-width="sm">
    <div class="flex items-center justify-between mb-md">
        <h3 class="font-bold text-lg text-brand-forest">Vente à la Pièce</h3>
        <button type="button" x-on:click="$dispatch('close-modal', { name: '{{ $name }}' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
    </div>
    @if($productNameProperty)
        <p class="text-xs text-outline mb-md">{{ $productNameProperty }}</p>
    @endif
    <div class="space-y-md">
        <div>
            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ $qtyLabel }}</label>
            <input type="number" step="1" min="1" wire:model="{{ $qtyModel }}" placeholder="ex : 2" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm focus:ring-2 focus:ring-brand-emerald outline-none">
            @error($qtyModel) <p class="invalid-feedback">{{ $message }}</p> @enderror
        </div>
        <div>
            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Montant Global de la Vente (FCFA)</label>
            <input type="number" wire:model="{{ $amountModel }}" placeholder="ex : 8000" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm focus:ring-2 focus:ring-brand-emerald outline-none">
            <p class="text-[10px] text-outline mt-xs">Vente à la pièce : saisir directement le montant total convenu pour l'ensemble de la quantité — jamais un prix unitaire multiplié automatiquement. Le prix indicatif n'est qu'une fourchette de référence.</p>
            @error($amountModel) <p class="invalid-feedback">{{ $message }}</p> @enderror
        </div>
    </div>
    <div class="flex justify-end gap-sm mt-lg">
        <button type="button" x-on:click="$dispatch('close-modal', { name: '{{ $name }}' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
        <button type="button" wire:click="{{ $confirmAction }}" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Ajouter au panier</button>
    </div>
</x-modal>
