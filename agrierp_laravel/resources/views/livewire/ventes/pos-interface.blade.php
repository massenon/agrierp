<div class="flex flex-col lg:flex-row gap-md mt-md" style="min-height: 60vh;">
    <div class="flex-1 lg:w-[65%] flex flex-col min-w-0">
        <div class="flex flex-wrap items-center gap-xs pb-sm">
            <div class="relative w-full sm:w-56">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher un produit..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-full text-xs bg-surface-zebra outline-none focus:ring-2 focus:ring-brand-emerald">
            </div>
            <a href="{{ route('stocks.produits.ajouter') }}" class="flex items-center gap-xs bg-white border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-[11px] px-sm py-2 rounded-full">
                <span class="material-symbols-outlined text-[16px]">add_box</span>Ajouter Produit Ferme
            </a>
            <button type="button" x-on:click="$dispatch('open-modal', { name: 'modal-livraison' })" class="flex items-center gap-xs bg-white border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-[11px] px-sm py-2 rounded-full">
                <span class="material-symbols-outlined text-[16px]">local_shipping</span>Livraison concernée
                @if($deliveryConcerned)
                    <span class="w-4 h-4 rounded-full bg-brand-emerald text-white text-[9px] font-bold flex items-center justify-center">✓</span>
                @endif
            </button>
        </div>

        <div class="flex gap-xs overflow-x-auto pb-sm">
            <button type="button" wire:click="$set('categoryFilter', '')" @class(['px-md py-1.5 rounded-full text-xs font-bold whitespace-nowrap', 'bg-brand-emerald text-white' => !$categoryFilter, 'border border-outline-variant text-outline' => $categoryFilter])>Tous</button>
            @foreach(\App\Models\ProductCategory::where('is_active', true)->orderBy('label')->get() as $cat)
                <button type="button" wire:click="$set('categoryFilter', '{{ $cat->label }}')" @class(['px-md py-1.5 rounded-full text-xs font-bold whitespace-nowrap', 'bg-brand-emerald text-white' => $categoryFilter === $cat->label, 'border border-outline-variant text-outline' => $categoryFilter !== $cat->label])>{{ $cat->label }}</button>
            @endforeach
        </div>

        <div class="flex-1 overflow-y-auto grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-4 gap-sm content-start max-h-[65vh]">
            @forelse($this->products as $product)
                <button type="button" wire:click="selectProduct('{{ $product->id }}')" wire:key="prod-{{ $product->id }}" class="bg-white border border-outline-variant rounded-lg p-sm text-left hover:border-brand-emerald hover:shadow-md transition-all">
                    <div class="w-full h-16 rounded-lg bg-surface-zebra flex items-center justify-center mb-xs">
                        <span class="material-symbols-outlined text-brand-emerald text-[28px]">inventory_2</span>
                    </div>
                    <p class="text-xs font-bold text-brand-forest truncate">{{ $product->name }}</p>
                    <p class="text-[10px] text-outline">
                        @if($product->pricing_mode === 'quote')
                            <span class="font-bold text-info-blue">Sur devis technique</span>
                        @else
                            {{ $product->price_display }}
                        @endif
                    </p>
                    <p class="text-[9px] {{ $product->is_stock_low ? 'text-error-deep font-bold' : 'text-outline' }} mt-0.5">Stock : {{ rtrim(rtrim(number_format($product->stock_qty, 2, '.', ''), '0'), '.') }} {{ $product->unit }}</p>
                </button>
            @empty
                <p class="col-span-full text-center text-xs text-outline py-lg">Aucun produit trouvé.</p>
            @endforelse
        </div>
    </div>

    <div class="lg:w-[35%] flex flex-col bg-white border border-outline-variant rounded-lg">
        <div class="p-md border-b border-outline-variant flex items-center justify-between flex-shrink-0">
            <h3 class="font-bold text-brand-forest text-sm">Panier de Vente</h3>
            <span class="w-6 h-6 rounded-full bg-brand-emerald text-white text-xs font-bold flex items-center justify-center">{{ count($cart) }}</span>
        </div>
        <div class="p-md space-y-sm border-b border-outline-variant flex-shrink-0">
            <label class="block text-[10px] text-brand-forest font-bold uppercase">Client</label>
            <div class="flex items-center gap-xs">
                <select wire:model="customerId" class="flex-1 h-10 px-md border border-outline-variant rounded-lg text-xs bg-white">
                    <option value="">Client Anonyme</option>
                    @foreach($this->customers as $customer)
                        <option value="{{ $customer->id }}">{{ $customer->name }}</option>
                    @endforeach
                </select>
                <button type="button" wire:click="openAddClientModal" class="w-10 h-10 flex items-center justify-center rounded-lg bg-brand-emerald text-white flex-shrink-0"><span class="material-symbols-outlined text-[18px]">person_add</span></button>
            </div>
            {{-- Ticket 15.32 — ÉCART ASSUMÉ avec la maquette (aucun champ date dans pos-interface.html) :
                 décision client du 14/10/2026, UN seul champ au panier. Ce n'est pas une modale. --}}
            <div>
                <label for="date-vente" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date de la vente</label>
                <input id="date-vente" dusk="date-vente" type="date" wire:model.live="dateVente" max="{{ $this->dateMax }}" @if($this->dateMin) min="{{ $this->dateMin }}" @endif class="w-full h-10 px-md border rounded-lg text-xs bg-white {{ $errors->has('dateVente') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('dateVente') <p class="invalid-feedback" dusk="date-vente-erreur">{{ $message }}</p> @enderror
                @if(! $errors->has('dateVente') && $dateVente !== '' && $dateVente < now()->format('Y-m-d'))
                    <p class="text-[10px] text-outline mt-xs">Vente antérieure : écriture, stock, créance et fiche seront datés du {{ \Carbon\Carbon::parse($dateVente)->format('d/m/Y') }}.</p>
                @endif
            </div>
        </div>

        <div class="flex-1 overflow-y-auto px-md py-md space-y-sm" style="max-height: 30vh;">
            @forelse($cart as $index => $item)
                <div class="flex items-start justify-between gap-xs bg-surface-zebra rounded-lg p-sm">
                    <div class="min-w-0">
                        <p class="text-xs font-bold text-brand-forest truncate">{{ $item['name'] }}</p>
                        <p class="text-[10px] text-outline">{{ $item['qty'] }} {{ $item['unit'] }}{{ $item['lot_code'] ? ' — '.$item['lot_code'] : '' }}</p>
                        <p class="text-xs font-bold text-brand-emerald">{{ number_format($item['montant'], 0, ',', ' ') }} FCFA</p>
                    </div>
                    <button type="button" wire:click="removeFromCart({{ $index }})" class="text-error-deep flex-shrink-0"><span class="material-symbols-outlined text-[18px]">close</span></button>
                </div>
            @empty
                <div class="flex flex-col items-center justify-center text-center px-md py-lg">
                    <span class="material-symbols-outlined text-outline-variant" style="font-size:40px;">shopping_cart</span>
                    <p class="text-xs text-outline mt-sm">Le panier est vide.<br>Sélectionnez un produit pour commencer.</p>
                </div>
            @endforelse
        </div>

        <div class="p-md border-t border-outline-variant space-y-sm flex-shrink-0">
            <div class="flex justify-between text-xs"><span class="text-outline">Sous-total</span><span class="font-bold">{{ number_format($this->subtotal, 0, ',', ' ') }} FCFA</span></div>
            <div class="flex justify-between items-center text-xs"><span class="text-outline">Remise (FCFA)</span><input wire:model.live="discount" type="number" min="0" class="w-24 h-8 px-sm border border-outline-variant rounded-lg text-right text-xs"></div>
            <div class="flex justify-between items-center border-t border-outline-variant pt-sm"><span class="font-bold text-brand-forest">Total à Payer</span><span class="text-lg font-extrabold text-brand-emerald">{{ number_format($this->total, 0, ',', ' ') }} FCFA</span></div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Mode de Règlement</label>
                <select wire:model.live="paymentMode" class="w-full h-10 px-md border border-outline-variant rounded-lg text-xs bg-white">
                    <option value="especes">Espèces</option>
                    <option value="mobile_money">Mobile Money</option>
                    <option value="virement">Virement bancaire</option>
                    <option value="credit">Crédit / À terme</option>
                    <option value="avance">Déduire de l'avance</option>
                </select>
            </div>
            @if($paymentMode === 'especes')
                <div class="grid grid-cols-2 gap-xs">
                    <div><label class="block text-[9px] text-outline font-bold uppercase mb-xs">Montant Reçu</label><input wire:model.live="cashReceived" type="number" min="0" placeholder="0" class="w-full h-9 px-sm border border-outline-variant rounded-lg text-xs"></div>
                    <div><label class="block text-[9px] text-outline font-bold uppercase mb-xs">Monnaie à Rendre</label><div class="h-9 flex items-center px-sm border border-outline-variant rounded-lg text-xs bg-surface-zebra font-bold">{{ number_format($this->changeDue, 0, ',', ' ') }} FCFA</div></div>
                </div>
            @endif
            <button type="button" wire:click="validateSale" dusk="validate-sale" wire:loading.attr="disabled" wire:target="validateSale" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm flex items-center justify-center gap-xs disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">point_of_sale</span>Valider la Vente
            </button>
        </div>
    </div>

    <x-modal name="modal-weight" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Vente à la Pièce</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-weight' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <p class="text-xs text-outline mb-md">{{ $this->weightProduct?->name }}</p>
        <div class="space-y-md">
            @if($this->weightProduct?->species_id)
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Bande Source *</label>
                    <select wire:model="weightLotId" dusk="weight-lot" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('weightLotId') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">-- Sélectionner --</option>
                        @foreach($this->lotsForWeightModal as $lot)
                            <option value="{{ $lot->id }}">{{ $lot->code }} ({{ $lot->current_quantity }} têtes)</option>
                        @endforeach
                    </select>
                    <p class="text-[10px] text-outline mt-xs">Nécessaire pour vérifier qu'aucun délai de rémanence vétérinaire n'est actif sur cette bande.</p>
                    @error('weightLotId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
            @endif
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nombre de sujets / Quantité</label>
                <input wire:model="weightQty" dusk="weight-qty" type="number" step="1" min="1" placeholder="ex : 2" class="w-full h-11 px-md border rounded-lg text-sm focus:ring-2 focus:ring-brand-emerald outline-none {{ $errors->has('weightQty') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('weightQty') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Montant Global de la Vente (FCFA)</label>
                <input wire:model="weightPrice" dusk="weight-price" type="number" placeholder="ex : 8000" class="w-full h-11 px-md border rounded-lg text-sm focus:ring-2 focus:ring-brand-emerald outline-none {{ $errors->has('weightPrice') ? 'is-invalid' : 'border-outline-variant' }}">
                <p class="text-[10px] text-outline mt-xs">Vente à la pièce : saisir directement le montant total convenu pour l'ensemble de la quantité — jamais un prix unitaire multiplié automatiquement.</p>
                @error('weightPrice') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
        </div>
        <div class="flex justify-end gap-sm mt-lg">
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-weight' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
            <button type="button" wire:click="confirmWeightAdd" dusk="weight-confirm" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Ajouter au panier</button>
        </div>
    </x-modal>

    <x-modal name="modal-add-client" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Nouveau Client</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-add-client' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveNewClient" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nom complet *</label>
                <input wire:model="newClientName" type="text" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('newClientName') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('newClientName') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Téléphone</label>
                <input wire:model="newClientPhone" type="tel" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-add-client' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>

    <x-modal name="modal-livraison" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Livraison</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-livraison' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <div class="space-y-md">
            <label class="flex items-center gap-xs text-xs text-outline">
                <input wire:model.live="deliveryConcerned" type="checkbox" class="h-3.5 w-3.5 rounded border-outline-variant text-brand-emerald">
                Livraison concernée (cages, sujets volumineux)
            </label>
            @if($deliveryConcerned)
                <div class="space-y-xs">
                    <select wire:model.live="deliveryMode" class="w-full h-9 px-md border border-outline-variant rounded-lg text-xs bg-white">
                        <option value="gratuite">Livraison gratuite (offerte)</option>
                        <option value="client">Livraison assurée par le client</option>
                        <option value="incluse">Prix de livraison inclus dans le montant</option>
                        <option value="facturee">Livraison facturée séparément</option>
                    </select>
                    @if($deliveryMode === 'facturee')
                        <input wire:model="deliveryFrais" type="number" placeholder="Frais de livraison (FCFA) si facturée séparément" class="w-full h-9 px-md border border-outline-variant rounded-lg text-xs">
                    @endif
                    <input wire:model="deliveryAdresse" type="text" placeholder="Adresse de livraison" class="w-full h-9 px-md border border-outline-variant rounded-lg text-xs">
                    <input wire:model="deliveryContact" type="text" placeholder="Contact du transporteur" class="w-full h-9 px-md border border-outline-variant rounded-lg text-xs">
                </div>
            @endif
        </div>
        <div class="flex justify-end gap-sm pt-md mt-md border-t border-outline-variant">
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-livraison' })" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Valider</button>
        </div>
    </x-modal>
</div>
