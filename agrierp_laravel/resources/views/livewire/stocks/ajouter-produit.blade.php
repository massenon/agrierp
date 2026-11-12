<div x-data="{ pricingMode: @entangle('pricing_mode') }">
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">{{ $productId ? 'edit' : 'add_box' }}</span>{{ $productId ? __('stocks.titre_modifier_produit') : __('stocks.titre_ajouter_produit') }}
        </h2>
        <p class="text-xs lg:text-sm text-outline mt-xs">{{ $productId ? __('stocks.desc_modifier_produit') : __('stocks.desc_ajouter_produit') }}</p>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm max-w-2xl">
        <form wire:submit="save" class="p-lg space-y-md" novalidate>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">{{ __('stocks.label_nom_produit') }}</label>
                <input wire:model="name" type="text" placeholder="{{ __('stocks.placeholder_nom_produit') }}" class="w-full h-11 px-md border rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none {{ $errors->has('name') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('name') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">{{ __('stocks.label_categorie') }}</label>
                    <select wire:model="category_id" class="w-full h-11 px-md border rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none {{ $errors->has('category_id') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">{{ __('stocks.select_selectionner') }}</option>
                        @foreach($this->categories as $cat)
                            <option value="{{ $cat->id }}">{{ $cat->label }}</option>
                        @endforeach
                    </select>
                    @error('category_id') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">{{ __('stocks.label_filiere_elevage') }} <span class="text-outline normal-case font-normal">{{ __('stocks.label_filiere_si_applicable') }}</span></label>
                    <select wire:model.live="species_id" class="w-full h-11 px-md border border-outline-variant rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none">
                        <option value="">{{ __('stocks.select_aucune') }}</option>
                        @foreach($this->speciesOptions as $sp)
                            <option value="{{ $sp->id }}">{{ $sp->label }}</option>
                        @endforeach
                    </select>
                </div>
            </div>

            @if($this->estAviculture)
                {{-- Ticket VOL-1 : la caisse range la vente de sujets vivants dans la catégorie d'effectif du produit. --}}
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">{{ __('stocks.label_categorie_effectif') }} <span class="text-outline normal-case font-normal">{{ __('stocks.label_categorie_effectif_vol') }}</span></label>
                    <select wire:model="categorie_effectif" class="w-full sm:max-w-[260px] h-11 px-md border rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none {{ $errors->has('categorie_effectif') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">{{ __('stocks.select_aucune') }}</option>
                        @foreach($this->categoriesEffectif as $groupe => $categories)
                            <optgroup label="{{ $groupe }}">
                                @foreach($categories as $cle => $libelle)
                                    <option value="{{ $cle }}">{{ $libelle }}</option>
                                @endforeach
                            </optgroup>
                        @endforeach
                    </select>
                    <p class="text-[10px] text-outline mt-xs">{{ __('stocks.info_categorie_effectif') }}</p>
                    @error('categorie_effectif') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
            @endif

            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">{{ __('stocks.label_unite_comptage') }}</label>
                <input wire:model="unit" type="text" placeholder="{{ __('stocks.placeholder_unite') }}" class="w-full sm:max-w-[160px] h-11 px-md border rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none {{ $errors->has('unit') ? 'is-invalid' : 'border-outline-variant' }}">
                <p class="text-[10px] text-outline mt-xs">{{ __('stocks.info_unite') }}</p>
                @error('unit') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            <div class="border-t border-outline-variant pt-md">
                <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">{{ __('stocks.label_mode_tarification') }}</label>
                <div class="flex gap-md">
                    <label class="flex items-center gap-xs cursor-pointer">
                        <input wire:model="pricing_mode" type="radio" value="fourchette" class="text-brand-emerald">
                        <span class="text-sm">{{ __('stocks.option_fourchette') }}</span>
                    </label>
                    <label class="flex items-center gap-xs cursor-pointer">
                        <input wire:model="pricing_mode" type="radio" value="quote" class="text-brand-emerald">
                        <span class="text-sm">{{ __('stocks.option_sur_devis') }}</span>
                    </label>
                </div>
                @error('pricing_mode') <p class="invalid-feedback">{{ $message }}</p> @enderror

                <div x-show="pricingMode === 'fourchette'" x-cloak class="flex items-center gap-xs mt-md">
                    <div class="flex-1">
                        <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">{{ __('stocks.label_prix_min') }}</label>
                        <input wire:model="price_min" type="number" placeholder="{{ __('stocks.placeholder_prix_min') }}" class="w-full h-11 px-md border rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none {{ $errors->has('price_min') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('price_min') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <span class="text-outline text-xs flex-shrink-0 mt-md">à</span>
                    <div class="flex-1">
                        <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">{{ __('stocks.label_prix_max') }}</label>
                        <input wire:model="price_max" type="number" placeholder="{{ __('stocks.placeholder_prix_max') }}" class="w-full h-11 px-md border rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none {{ $errors->has('price_max') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('price_max') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                </div>
                <p x-show="pricingMode === 'quote'" x-cloak class="text-xs text-outline mt-md bg-surface-zebra rounded-lg p-sm">{{ __('stocks.info_sur_devis') }}</p>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-3 gap-md border-t border-outline-variant pt-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">{{ __('stocks.label_stock_initial') }}</label>
                    <input wire:model="stock_qty" type="number" step="0.01" class="w-full h-11 px-md border border-outline-variant rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">{{ __('stocks.label_seuil_alerte') }}</label>
                    <input wire:model="alert_threshold" type="number" step="0.01" class="w-full h-11 px-md border border-outline-variant rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">{{ __('stocks.label_tva') }}</label>
                    <input wire:model="tva_rate" type="number" step="0.01" class="w-full h-11 px-md border border-outline-variant rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none">
                </div>
            </div>

            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">{{ __('stocks.label_description') }}</label>
                <textarea wire:model="description" rows="3" class="w-full px-md py-sm border border-outline-variant rounded-lg bg-white text-sm focus:ring-2 focus:ring-brand-emerald outline-none"></textarea>
            </div>

            <div class="flex justify-end gap-sm pt-md border-t border-outline-variant">
                <a wire:navigate href="/catalogue-produits" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('stocks.bouton_annuler') }}</a>
                <button type="submit" wire:loading.attr="disabled" wire:target="save" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest disabled:opacity-50">
                    {{ $productId ? __('stocks.bouton_enregistrer_modif') : __('stocks.bouton_enregistrer') }}
                </button>
            </div>
        </form>
    </div>
</div>
