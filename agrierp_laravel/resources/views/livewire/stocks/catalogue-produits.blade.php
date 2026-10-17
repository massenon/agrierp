<div>
    <x-tab-page
        :tabs="[
            ['key' => 'catalogue', 'label' => 'Voir le Catalogue', 'icon' => 'storefront'],
            ['key' => 'seuils', 'label' => 'Seuils d\'Alerte', 'icon' => 'warning'],
        ]"
        :active="$tab">

        @if($tab === 'catalogue')
            <div x-data="{ view: 'grid' }">
                <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md mb-lg">
                    <div>
                        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                            <span class="material-symbols-outlined text-brand-emerald text-[26px]">storefront</span>Catalogue Produits
                        </h2>
                        <p class="text-xs text-outline mt-xs">Vue d'ensemble visuelle de l'offre commerciale de la ferme.</p>
                    </div>
                    <div class="flex items-center gap-xs">
                        <div class="flex items-center bg-white border border-outline-variant rounded-lg overflow-hidden">
                            <button type="button" @click="view = 'grid'" :class="view === 'grid' ? 'bg-brand-emerald text-white' : 'text-outline hover:bg-surface-zebra'" class="px-sm py-2"><span class="material-symbols-outlined text-[18px]">grid_view</span></button>
                            <button type="button" @click="view = 'list'" :class="view === 'list' ? 'bg-brand-emerald text-white' : 'text-outline hover:bg-surface-zebra'" class="px-sm py-2"><span class="material-symbols-outlined text-[18px]">view_list</span></button>
                        </div>
                        <a href="{{ route('stocks.produits.ajouter') }}" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                            <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouveau Produit
                        </a>
                    </div>
                </div>

                <div class="flex gap-xs overflow-x-auto pb-md mb-md">
                    <button type="button" wire:click="$set('category', '')" @class(['px-md py-1.5 rounded-full text-xs font-bold whitespace-nowrap', 'bg-brand-emerald text-white' => $category === '', 'border border-outline-variant text-outline' => $category !== ''])>Tous</button>
                    @foreach($this->categories as $cat)
                        <button type="button" wire:click="$set('category', '{{ $cat->label }}')" @class(['px-md py-1.5 rounded-full text-xs font-bold whitespace-nowrap', 'bg-brand-emerald text-white' => $category === $cat->label, 'border border-outline-variant text-outline' => $category !== $cat->label])>{{ $cat->label }}</button>
                    @endforeach
                </div>

                <div class="relative max-w-sm mb-md">
                    <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                    <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher un produit ou un SKU..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
                </div>

                @php
                    $categoryIcons = [
                        'Cuniculture' => 'cruelty_free', 'Aviculture' => 'egg', 'Porciculture' => 'pets',
                        'Maraîchage' => 'nutrition', 'Transformation' => 'eco', 'Équipements' => 'inventory_2',
                    ];
                @endphp

                @if($this->products->isEmpty())
                    <p class="text-xs text-outline text-center py-xl">Aucun produit ne correspond à cette recherche.</p>
                @else
                    <div x-show="view === 'grid'" class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-4 gap-md">
                        @foreach($this->products as $product)
                            <div class="relative bg-white border border-outline-variant rounded-lg p-md hover:shadow-md transition-all">
                                <span class="absolute top-2 left-2 text-[9px] font-bold px-1.5 py-0.5 rounded {{ $product->is_stock_low ? 'bg-error-red text-white' : 'bg-brand-emerald/90 text-white' }}">S: {{ rtrim(rtrim(number_format($product->stock_qty, 2, '.', ''), '0'), '.') }} {{ $product->unit }}</span>
                                <div class="flex justify-end gap-1 mb-sm">
                                    <a href="{{ route('stocks.produits.modifier', $product->id) }}" class="text-outline hover:text-brand-forest p-1"><span class="material-symbols-outlined text-[16px]">edit</span></a>
                                    <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-{{ $product->id }}' })" class="text-outline hover:text-error-deep p-1"><span class="material-symbols-outlined text-[16px]">archive</span></button>
                                </div>
                                <div class="flex flex-col items-center text-center gap-1 pt-sm">
                                    <span class="material-symbols-outlined text-brand-emerald" style="font-size:36px;">{{ $categoryIcons[$product->category?->label] ?? 'inventory_2' }}</span>
                                    <p class="text-[9px] text-outline font-mono">{{ $product->sku }}</p>
                                    <p class="text-xs font-bold text-on-surface">{{ $product->name }}</p>
                                    <p class="text-[10px] text-outline">{{ $product->category?->label }}</p>
                                    <p class="text-xs font-bold text-brand-emerald mt-1">{{ $product->price_display }}</p>
                                </div>
                            </div>
                            <x-modal-confirm-delete :name="'archive-'.$product->id" :item-label="$product->name" :action="'archive(\''.$product->id.'\')'" />
                        @endforeach
                    </div>

                    <div x-show="view === 'list'" x-cloak class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                        <div class="overflow-x-auto">
                            <table class="w-full rtable">
                                <thead class="bg-surface-zebra border-b border-outline-variant">
                                    <tr>
                                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">SKU</th>
                                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Désignation</th>
                                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Catégorie</th>
                                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Stock</th>
                                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Tarif</th>
                                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    @foreach($this->products as $i => $product)
                                        <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                            <td data-label="SKU" class="px-md py-sm text-xs font-mono">{{ $product->sku }}</td>
                                            <td data-label="Désignation" class="px-md py-sm text-xs font-semibold">{{ $product->name }}</td>
                                            <td data-label="Catégorie" class="px-md py-sm text-xs">{{ $product->category?->label }}</td>
                                            <td data-label="Stock" class="px-md py-sm text-xs text-right {{ $product->is_stock_low ? 'text-error-deep font-bold' : '' }}">{{ rtrim(rtrim(number_format($product->stock_qty, 2, '.', ''), '0'), '.') }} {{ $product->unit }}</td>
                                            <td data-label="Tarif" class="px-md py-sm text-xs text-right font-bold text-brand-emerald">{{ $product->price_display }}</td>
                                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                                <a href="{{ route('stocks.produits.modifier', $product->id) }}" class="text-outline hover:text-brand-forest p-1 inline-block"><span class="material-symbols-outlined text-[16px]">edit</span></a>
                                                <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-{{ $product->id }}' })" class="text-outline hover:text-error-deep p-1"><span class="material-symbols-outlined text-[16px]">archive</span></button>
                                            </td>
                                        </tr>
                                    @endforeach
                                </tbody>
                            </table>
                        </div>
                    </div>
                @endif
            </div>
        @endif

        @if($tab === 'seuils')
            <livewire:stocks.seuils-alerte />
        @endif
    </x-tab-page>
</div>
