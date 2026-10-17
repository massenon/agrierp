<div class="mt-md">
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface">Enregistrer un Achat</h2>
        <p class="text-xs text-outline mt-xs">Réception de marchandises auprès d'un fournisseur.</p>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-[65%_35%] gap-md items-start">
        <div class="space-y-md">
            <div class="bg-white border border-outline-variant rounded-lg p-md">
                <label class="block text-[10px] text-outline font-bold uppercase mb-xs">Sélectionner Fournisseur</label>
                <div class="flex items-center gap-xs">
                    <select wire:model="supplierId" class="flex-1 h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('supplierId') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">Choisir le fournisseur...</option>
                        @foreach($this->suppliers as $supplier)
                            <option value="{{ $supplier->id }}">{{ $supplier->name }}</option>
                        @endforeach
                    </select>
                    <button type="button" wire:click="openAddSupplierModal" class="w-11 h-11 flex items-center justify-center rounded-lg bg-brand-emerald hover:bg-brand-forest text-white flex-shrink-0" title="Ajouter un fournisseur">
                        <span class="material-symbols-outlined text-[20px]">person_add</span>
                    </button>
                </div>
                @error('supplierId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            <div class="bg-white border border-outline-variant rounded-lg p-md">
                <label class="block text-[10px] text-outline font-bold uppercase mb-sm">Ajouter un Article</label>
                <div class="grid grid-cols-1 sm:grid-cols-[1fr_auto_100px_120px] gap-sm items-end">
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-1">Produit / Article</label>
                        <select wire:model.live="lineProductId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('lineProductId') ? 'is-invalid' : 'border-outline-variant' }}">
                            <option value="">Choisir un produit...</option>
                            @foreach($this->products as $product)
                                <option value="{{ $product->id }}">{{ $product->name }}</option>
                            @endforeach
                        </select>
                    </div>
                    <button type="button" wire:click="openAddProductModal" class="w-11 h-11 flex items-center justify-center rounded-lg bg-brand-emerald hover:bg-brand-forest text-white flex-shrink-0" title="Ajouter un produit">
                        <span class="material-symbols-outlined text-[20px]">add_box</span>
                    </button>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-1">Quantité</label>
                        <input wire:model="lineQty" type="number" min="1" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('lineQty') ? 'is-invalid' : 'border-outline-variant' }}">
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-1">Prix Unitaire</label>
                        <input wire:model="linePrice" type="number" min="0" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('linePrice') ? 'is-invalid' : 'border-outline-variant' }}">
                    </div>
                </div>
                <button type="button" wire:click="addLine" class="w-full mt-md py-sm rounded-lg border-2 border-brand-emerald text-brand-emerald font-bold text-sm hover:bg-brand-emerald/5 flex items-center justify-center gap-xs">
                    <span class="material-symbols-outlined text-[18px]">add</span>Ajouter au bon d'achat
                </button>

                @if(empty($cart))
                    <div class="flex flex-col items-center justify-center py-xl text-center">
                        <span class="material-symbols-outlined text-outline-variant" style="font-size:56px;">inventory_2</span>
                        <p class="text-sm text-outline mt-sm">Aucun article ajouté au bon d'achat pour le moment.</p>
                    </div>
                @else
                    <div class="overflow-x-auto mt-md">
                        <table class="w-full text-xs">
                            <thead><tr class="text-outline border-b border-outline-variant"><th class="text-left py-xs">Désignation</th><th class="text-right py-xs">Qté</th><th class="text-right py-xs">P.U</th><th class="text-right py-xs">Total</th><th></th></tr></thead>
                            <tbody>
                                @foreach($cart as $index => $item)
                                    <tr class="border-b border-outline-variant/50">
                                        <td class="py-xs font-bold text-brand-forest">{{ $item['name'] }}</td>
                                        <td class="py-xs text-right">{{ $item['qty'] }} {{ $item['unit'] }}</td>
                                        <td class="py-xs text-right">{{ number_format($item['unit_price'], 0, ',', ' ') }}</td>
                                        <td class="py-xs text-right font-bold">{{ number_format($item['qty'] * $item['unit_price'], 0, ',', ' ') }}</td>
                                        <td class="py-xs text-right"><button type="button" wire:click="removeLine({{ $index }})" class="text-error-deep"><span class="material-symbols-outlined text-[16px]">close</span></button></td>
                                    </tr>
                                @endforeach
                            </tbody>
                        </table>
                    </div>
                @endif
            </div>
        </div>

        <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md sticky top-4">
            <div class="flex items-center gap-xs text-brand-forest font-bold text-sm border-b border-outline-variant pb-sm">
                <span class="material-symbols-outlined text-[20px]">receipt_long</span>Résumé de la Facture
            </div>

            <div class="bg-accent-yellow/20 border border-accent-yellow rounded-lg p-md flex items-center justify-between">
                <span class="text-xs font-bold text-brand-forest uppercase">Montant Total</span>
                <span class="text-2xl font-extrabold text-brand-forest">{{ number_format($this->total, 0, ',', ' ') }} FCFA</span>
            </div>

            <div>
                <label class="block text-[10px] text-outline font-bold uppercase mb-xs">Mode de Paiement</label>
                <select wire:model="paymentMode" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                    <option value="especes">Caisse (Espèces)</option>
                    <option value="virement">Virement Bancaire</option>
                    <option value="mobile_money">Mobile Money</option>
                    <option value="credit">Crédit Fournisseur</option>
                </select>
            </div>
            <div>
                <label class="block text-[10px] text-outline font-bold uppercase mb-xs">Compte Débité *</label>
                <select wire:model="treasuryAccountId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('treasuryAccountId') ? 'is-invalid' : 'border-outline-variant' }}">
                    @foreach($this->treasuryAccounts as $account)
                        <option value="{{ $account->id }}">{{ $account->label }} ({{ number_format($account->balance, 0, ',', ' ') }} FCFA)</option>
                    @endforeach
                </select>
                @error('treasuryAccountId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-outline font-bold uppercase mb-xs">Montant Payé (FCFA)</label>
                <input wire:model="amountPaid" type="number" min="0" placeholder="0" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                <p class="text-[10px] text-outline mt-xs">Si inférieur au total, une dette fournisseur est créée pour le solde.</p>
            </div>

            <div>
                <label class="block text-[10px] text-outline font-bold uppercase mb-xs">Pièce Justificative</label>
                <label class="border-2 border-dashed border-outline-variant rounded-lg p-lg text-center block cursor-pointer hover:border-brand-emerald">
                    <input wire:model="receiptFile" type="file" accept="image/*" class="hidden">
                    <span class="material-symbols-outlined text-outline-variant" style="font-size:36px;">add_a_photo</span>
                    <p class="text-xs text-outline mt-xs font-semibold">{{ $receiptFile ? $receiptFile->getClientOriginalName() : 'Associer une photo du reçu' }}</p>
                    <p class="text-[10px] text-outline">Format JPG, PNG (Max 5Mo)</p>
                </label>
                @error('receiptFile') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            <button type="button" wire:click="submitAchat" wire:loading.attr="disabled" wire:target="submitAchat" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm flex items-center justify-center gap-xs disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">check_circle</span>Enregistrer l'Achat
            </button>
        </div>
    </div>

    <div class="mt-xl bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="px-md py-sm border-b border-outline-variant"><h3 class="text-sm font-bold text-brand-forest">Achats Récemment Enregistrés</h3></div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Référence</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Fournisseur</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Montant</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->recentPurchases as $i => $purchase)
                        <tr class="border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td class="px-md py-sm text-xs font-mono font-bold text-brand-emerald">{{ strtoupper(substr($purchase->id, 0, 8)) }}</td>
                            <td class="px-md py-sm text-xs font-bold text-brand-forest">{{ $purchase->supplier?->name }}</td>
                            <td class="px-md py-sm text-xs">{{ $purchase->purchase_date->format('d/m/Y') }}</td>
                            <td class="px-md py-sm text-xs text-right font-bold">{{ number_format($purchase->total, 0, ',', ' ') }} FCFA</td>
                        </tr>
                    @empty
                        <tr><td colspan="4" class="px-md py-lg text-center text-outline">Aucun achat enregistré pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-add-supplier" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Nouveau Fournisseur</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-add-supplier' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveNewSupplier" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Raison sociale *</label>
                <input wire:model="newSupplierName" type="text" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('newSupplierName') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('newSupplierName') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Téléphone *</label>
                <input wire:model="newSupplierPhone" type="tel" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('newSupplierPhone') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('newSupplierPhone') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-add-supplier' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>

    <x-modal name="modal-add-product" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Nouveau Produit</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-add-product' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveNewProduct" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nom du produit *</label>
                <input wire:model="newProductName" type="text" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('newProductName') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('newProductName') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Catégorie *</label>
                <select wire:model="newProductCategoryId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('newProductCategoryId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->categories as $cat)
                        <option value="{{ $cat->id }}">{{ $cat->label }}</option>
                    @endforeach
                </select>
                @error('newProductCategoryId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Unité</label>
                <input wire:model="newProductUnit" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <p class="text-[10px] text-outline bg-surface-zebra rounded-lg p-sm">La tarification (Fourchette/Sur devis) se complète ensuite depuis le Catalogue Produits.</p>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-add-product' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>
</div>
