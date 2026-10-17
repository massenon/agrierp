<div x-data="{ pricingMode: @entangle('pricing_mode') }">
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">{{ $productId ? 'edit' : 'add_box' }}</span>{{ $productId ? 'Modifier le Produit' : 'Ajouter un Produit' }}
        </h2>
        <p class="text-xs lg:text-sm text-outline mt-xs">{{ $productId ? 'Modification d\'une référence existante du catalogue.' : 'Création d\'une nouvelle référence dans le catalogue produits de la ferme.' }}</p>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm max-w-2xl">
        <form wire:submit="save" class="p-lg space-y-md" novalidate>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">Nom du produit *</label>
                <input wire:model="name" type="text" placeholder="ex : Œufs de table (plateau de 30)" class="w-full h-11 px-md border rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none {{ $errors->has('name') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('name') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">Catégorie *</label>
                    <select wire:model="category_id" class="w-full h-11 px-md border rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none {{ $errors->has('category_id') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">-- Sélectionner --</option>
                        @foreach($this->categories as $cat)
                            <option value="{{ $cat->id }}">{{ $cat->label }}</option>
                        @endforeach
                    </select>
                    @error('category_id') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">Filière d'élevage <span class="text-outline normal-case font-normal">(si applicable)</span></label>
                    <select wire:model="species_id" class="w-full h-11 px-md border border-outline-variant rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none">
                        <option value="">-- Aucune --</option>
                        @foreach($this->speciesOptions as $sp)
                            <option value="{{ $sp->id }}">{{ $sp->label }}</option>
                        @endforeach
                    </select>
                </div>
            </div>

            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">Unité de comptage *</label>
                <input wire:model="unit" type="text" placeholder="ex : u, sac, plateau" class="w-full sm:max-w-[160px] h-11 px-md border rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none {{ $errors->has('unit') ? 'is-invalid' : 'border-outline-variant' }}">
                <p class="text-[10px] text-outline mt-xs">Toujours une unité de pièce/comptage — jamais une unité de poids (kg).</p>
                @error('unit') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            <div class="border-t border-outline-variant pt-md">
                <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">Mode de Tarification *</label>
                <div class="flex gap-md">
                    <label class="flex items-center gap-xs cursor-pointer">
                        <input wire:model="pricing_mode" type="radio" value="fourchette" class="text-brand-emerald">
                        <span class="text-sm">Fourchette</span>
                    </label>
                    <label class="flex items-center gap-xs cursor-pointer">
                        <input wire:model="pricing_mode" type="radio" value="quote" class="text-brand-emerald">
                        <span class="text-sm">Sur devis</span>
                    </label>
                </div>
                @error('pricing_mode') <p class="invalid-feedback">{{ $message }}</p> @enderror

                <div x-show="pricingMode === 'fourchette'" x-cloak class="flex items-center gap-xs mt-md">
                    <div class="flex-1">
                        <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">Prix Min (FCFA) *</label>
                        <input wire:model="price_min" type="number" placeholder="ex : 3000" class="w-full h-11 px-md border rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none {{ $errors->has('price_min') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('price_min') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <span class="text-outline text-xs flex-shrink-0 mt-md">à</span>
                    <div class="flex-1">
                        <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">Prix Max (FCFA) *</label>
                        <input wire:model="price_max" type="number" placeholder="ex : 4000" class="w-full h-11 px-md border rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none {{ $errors->has('price_max') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('price_max') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                </div>
                <p x-show="pricingMode === 'quote'" x-cloak class="text-xs text-outline mt-md bg-surface-zebra rounded-lg p-sm">Ce produit sera vendu sur devis (ex. cages sur mesure) — aucun prix indicatif à saisir ici.</p>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-3 gap-md border-t border-outline-variant pt-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">Stock Initial</label>
                    <input wire:model="stock_qty" type="number" step="0.01" class="w-full h-11 px-md border border-outline-variant rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">Seuil d'Alerte</label>
                    <input wire:model="alert_threshold" type="number" step="0.01" class="w-full h-11 px-md border border-outline-variant rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">TVA (%)</label>
                    <input wire:model="tva_rate" type="number" step="0.01" class="w-full h-11 px-md border border-outline-variant rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none">
                </div>
            </div>

            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">Description</label>
                <textarea wire:model="description" rows="3" class="w-full px-md py-sm border border-outline-variant rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none"></textarea>
            </div>

            <div class="flex justify-end gap-sm pt-md border-t border-outline-variant">
                <a href="/catalogue-produits" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</a>
                <button type="submit" wire:loading.attr="disabled" wire:target="save" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest disabled:opacity-50">
                    {{ $productId ? 'Enregistrer les modifications' : 'Enregistrer' }}
                </button>
            </div>
        </form>
    </div>
</div>
