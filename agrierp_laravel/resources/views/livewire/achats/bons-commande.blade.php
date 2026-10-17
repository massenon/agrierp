<div class="mt-md">
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface">Bons de Commande</h2>
        <p class="text-xs text-outline mt-xs">Planification des approvisionnements de la ferme.</p>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-lg">
        <div class="flex items-center gap-xs mb-xs text-brand-forest font-bold text-sm">
            <span class="material-symbols-outlined text-brand-emerald text-[20px]">assignment_turned_in</span>Saisie d'un Bon de Commande
        </div>
        <p class="text-xs text-outline mb-md">Générer un ordre d'achat prévisionnel multi-produits.</p>

        <div class="grid grid-cols-1 md:grid-cols-5 gap-md items-end">
            <div>
                <label class="block text-[9px] text-outline font-bold uppercase mb-1">Fournisseur</label>
                <select wire:model="supplierId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('supplierId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">Choisir le fournisseur...</option>
                    @foreach($this->suppliers as $supplier)
                        <option value="{{ $supplier->id }}">{{ $supplier->name }}</option>
                    @endforeach
                </select>
                @error('supplierId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="border-l-4 border-brand-forest pl-sm">
                <label class="block text-[9px] text-outline font-bold uppercase mb-1">Date de Livraison Attendue</label>
                <input wire:model="expectedDeliveryDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div>
                <label class="block text-[9px] text-outline font-bold uppercase mb-1">Produit / Article</label>
                <select wire:model.live="lineProductId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('lineProductId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">Choisir un produit...</option>
                    @foreach($this->products as $product)
                        <option value="{{ $product->id }}">{{ $product->name }}</option>
                    @endforeach
                </select>
            </div>
            <div>
                <label class="block text-[9px] text-outline font-bold uppercase mb-1">Quantité</label>
                <input wire:model="lineQty" type="number" min="1" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('lineQty') ? 'is-invalid' : 'border-outline-variant' }}">
            </div>
            <div>
                <label class="block text-[9px] text-outline font-bold uppercase mb-1">P.U Estimé (FCFA)</label>
                <input wire:model="linePrice" type="number" min="0" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('linePrice') ? 'is-invalid' : 'border-outline-variant' }}">
            </div>
        </div>
        <button type="button" wire:click="addLine" class="w-full mt-md py-sm rounded-lg border-2 border-brand-emerald text-brand-emerald font-bold text-sm hover:bg-brand-emerald/5 flex items-center justify-center gap-xs">
            <span class="material-symbols-outlined text-[18px]">add</span>Ajouter au bon de commande
        </button>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-[65%_35%] gap-md mb-xl">
        <div class="bg-white border border-outline-variant rounded-lg p-md">
            <div class="flex items-center gap-xs text-brand-forest font-bold text-sm mb-md"><span class="material-symbols-outlined text-[20px]">shopping_basket</span>Articles Prévisionnels de la Commande</div>
            @if(empty($cart))
                <div class="flex flex-col items-center justify-center py-xl text-center">
                    <span class="material-symbols-outlined text-outline-variant" style="font-size:56px;">assignment</span>
                    <p class="text-sm text-outline mt-sm">Aucun article ajouté au bon de commande.</p>
                </div>
            @else
                <div class="overflow-x-auto">
                    <table class="w-full text-xs">
                        <thead><tr class="text-outline border-b border-outline-variant"><th class="text-left py-xs">Produit</th><th class="text-right py-xs">Qté</th><th class="text-right py-xs">P.U</th><th class="text-right py-xs">Total</th><th></th></tr></thead>
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
        <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
            <div class="bg-accent-yellow/20 border border-accent-yellow rounded-lg p-md flex items-center justify-between">
                <span class="text-xs font-bold text-brand-forest uppercase">Total Estimé</span>
                <span class="text-2xl font-extrabold text-brand-forest">{{ number_format($this->total, 0, ',', ' ') }} FCFA</span>
            </div>
            <div class="bg-info-blue/10 border border-info-blue/30 rounded-lg p-md text-[11px] text-brand-forest flex gap-xs">
                <span class="material-symbols-outlined text-info-blue text-[18px] flex-shrink-0">info</span>
                <span>Rappel : Ces articles d'approvisionnement (aliments, vaccins) sont stockés dans le module Stocks (Classe 3) et ne seront jamais mélangés avec vos produits finis de la ferme (Classe 7).</span>
            </div>
            <button type="button" wire:click="generateBc" wire:loading.attr="disabled" wire:target="generateBc" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm flex items-center justify-center gap-xs disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">check_circle</span>Générer le Bon
            </button>
        </div>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="bg-brand-forest text-white px-md py-sm flex items-center justify-between">
            <h3 class="text-sm font-bold">Bons de commande émis</h3>
            <span class="material-symbols-outlined text-[18px]">history</span>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Réf Commande</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date d'Émission</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Livraison Attendue</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Fournisseur</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Montant Estimé</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->orders as $i => $order)
                        @php
                            $orderTotal = $order->lines->sum(fn($l) => $l->qty * $l->estimated_unit_price);
                            $statusStyles = ['brouillon' => 'bg-surface-zebra text-outline border-outline-variant', 'envoye' => 'bg-info-blue/10 text-info-blue border-info-blue/30', 'recu' => 'bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30', 'annule' => 'bg-error-bg text-error-deep border-error-deep/30'];
                            $statusLabels = ['brouillon' => 'BROUILLON', 'envoye' => 'ENVOYÉ / EN COURS', 'recu' => 'REÇU / VALIDÉ', 'annule' => 'ANNULÉ'];
                        @endphp
                        <tr class="rrow {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} border-b border-outline-variant">
                            <td data-label="Réf" class="px-md py-sm text-xs font-bold font-mono text-brand-emerald">{{ strtoupper(substr($order->id, 0, 8)) }}</td>
                            <td data-label="Émission" class="px-md py-sm text-xs">{{ $order->created_at->format('d/m/Y') }}</td>
                            <td data-label="Livraison" class="px-md py-sm text-xs">{{ $order->expected_delivery_date?->format('d/m/Y') ?? '—' }}</td>
                            <td data-label="Fournisseur" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $order->supplier?->name }}</td>
                            <td data-label="Montant" class="px-md py-sm text-xs text-right font-bold">{{ number_format($orderTotal, 0, ',', ' ') }}</td>
                            <td data-label="Statut" class="px-md py-sm"><span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border {{ $statusStyles[$order->status] }}">{{ $statusLabels[$order->status] }}</span></td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button" wire:click="exportPdf('{{ $order->id }}')" class="text-outline hover:text-brand-forest p-1" title="Exporter PDF"><span class="material-symbols-outlined text-[18px]">print</span></button>
                                @if($order->status !== 'recu' && $order->status !== 'annule')
                                    <button type="button" wire:click="openReceiveModal('{{ $order->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="Valider la réception"><span class="material-symbols-outlined text-[18px]">assignment_turned_in</span></button>
                                @endif
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="7" class="px-md py-lg text-center text-outline">Aucun bon de commande émis pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-receive-order" max-width="sm">
        <div class="text-center">
            <span class="material-symbols-outlined text-brand-emerald" style="font-size:52px;">assignment_turned_in</span>
            <h3 class="font-bold text-lg text-brand-forest mt-sm">Valider la réception</h3>
            <p class="text-xs text-outline mt-xs">Contrôle de validation et intégration aux stocks physiques</p>
            <div class="bg-brand-emerald/10 border border-brand-emerald/20 rounded-lg p-md mt-md text-[11px] text-brand-forest text-left">
                La validation de la réception générera automatiquement une facture d'achat formelle et incrémentera vos stocks de marchandises physiques en base locale.
            </div>
            <div class="flex justify-center gap-sm mt-lg">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-receive-order' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="button" wire:click="confirmReceiveOrder" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Confirmer la Réception</button>
            </div>
        </div>
    </x-modal>
</div>
