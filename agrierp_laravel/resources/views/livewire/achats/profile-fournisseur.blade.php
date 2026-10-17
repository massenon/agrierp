<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface">Profil Fournisseur</h2>
        <p class="text-xs text-outline mt-xs">Fiche complète, historique et créances du tiers.</p>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-[35%_65%] gap-md items-start">
        <div class="bg-white border border-outline-variant rounded-lg p-lg text-center space-y-md">
            <div class="w-16 h-16 rounded-full bg-brand-emerald text-white flex items-center justify-center text-xl font-extrabold mx-auto">
                {{ strtoupper(collect(explode(' ', $supplier->name))->map(fn($p) => mb_substr($p, 0, 1))->take(2)->implode('')) }}
            </div>
            <div>
                <p class="font-bold text-brand-forest">{{ $supplier->name }}</p>
                <p class="text-xs text-outline">{{ $supplier->phone ?? '—' }}</p>
            </div>
            @if($supplier->category)
                <span class="inline-block text-[10px] font-bold px-sm py-1 rounded-full bg-info-blue/10 text-info-blue border border-info-blue/30">{{ $supplier->category }}</span>
            @endif
            <div class="bg-surface-zebra rounded-lg p-md">
                <p class="text-[10px] text-outline font-bold uppercase">Solde Global Dû</p>
                <p class="text-xl font-extrabold {{ $this->soldeGlobal > 0 ? 'text-error-deep' : 'text-brand-emerald' }}">{{ number_format($this->soldeGlobal, 0, ',', ' ') }} FCFA</p>
            </div>

            <div class="space-y-xs">
                <a href="{{ route('achats.fournisseurs-hub') }}?tab=fiches" class="block w-full py-sm rounded-lg border border-outline-variant text-xs font-bold text-brand-forest hover:bg-surface-zebra">Modifier la fiche</a>
                <button type="button" wire:click="openRegularisation" class="w-full py-sm rounded-lg bg-brand-emerald text-white text-xs font-bold hover:bg-brand-forest">Enregistrer un règlement</button>
            </div>
        </div>

        <div class="bg-white border border-outline-variant rounded-lg p-md">
            <div class="flex items-center gap-xs border-b border-outline-variant mb-md overflow-x-auto">
                <button type="button" wire:click="$set('tab', 'achats')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'achats' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">Achats</button>
                <button type="button" wire:click="$set('tab', 'dettes')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'dettes' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">Dettes</button>
                <button type="button" wire:click="$set('tab', 'commandes')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'commandes' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">Commandes</button>
            </div>

            @if($tab === 'achats')
                <table class="w-full text-xs">
                    <thead><tr class="text-outline border-b border-outline-variant"><th class="text-left py-xs">Référence</th><th class="text-left py-xs">Date</th><th class="text-left py-xs">Catégorie</th><th class="text-right py-xs">Montant</th><th class="text-left py-xs">Statut</th></tr></thead>
                    <tbody>
                        @forelse($this->purchases as $i => $purchase)
                            <tr class="border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : '' }}">
                                <td class="py-xs font-mono">{{ strtoupper(substr($purchase->id, 0, 8)) }}</td>
                                <td class="py-xs">{{ $purchase->purchase_date->format('d/m/Y') }}</td>
                                <td class="py-xs">{{ $purchase->lines->first()?->product?->category?->label ?? '—' }}</td>
                                <td class="py-xs text-right">{{ number_format($purchase->total, 0, ',', ' ') }}</td>
                                <td class="py-xs">
                                    @if($purchase->payment_mode === 'comptant')
                                        <span class="text-brand-emerald font-bold">Payé</span>
                                    @else
                                        <span class="text-error-deep font-bold">Crédit</span>
                                    @endif
                                </td>
                            </tr>
                        @empty
                            <tr><td colspan="5" class="py-md text-center text-outline">Aucun achat auprès de ce fournisseur.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            @endif

            @if($tab === 'dettes')
                @if($this->debts->isEmpty())
                    <p class="text-xs text-outline">Aucune dette active auprès de ce fournisseur — tous les achats sont réglés.</p>
                @else
                    <table class="w-full text-xs">
                        <thead><tr class="text-outline border-b border-outline-variant"><th class="text-left py-xs">Facture</th><th class="text-left py-xs">Échéance</th><th class="text-right py-xs">Solde Dû</th></tr></thead>
                        <tbody>
                            @foreach($this->debts as $debt)
                                <tr class="border-b border-outline-variant">
                                    <td class="py-xs font-mono">{{ strtoupper(substr($debt->purchase_id ?? $debt->id, 0, 8)) }}</td>
                                    <td class="py-xs">{{ $debt->due_date->format('d/m/Y') }}</td>
                                    <td class="py-xs text-right font-bold text-error-deep">{{ number_format($debt->balance, 0, ',', ' ') }}</td>
                                </tr>
                            @endforeach
                        </tbody>
                    </table>
                @endif
            @endif

            @if($tab === 'commandes')
                <table class="w-full text-xs">
                    <thead><tr class="text-outline border-b border-outline-variant"><th class="text-left py-xs">BC N°</th><th class="text-left py-xs">Émission</th><th class="text-left py-xs">Livraison</th><th class="text-right py-xs">Statut</th></tr></thead>
                    <tbody>
                        @forelse($this->orders as $order)
                            <tr class="border-b border-outline-variant">
                                <td class="py-xs font-mono">{{ strtoupper(substr($order->id, 0, 8)) }}</td>
                                <td class="py-xs">{{ $order->created_at->format('d/m/Y') }}</td>
                                <td class="py-xs">{{ $order->expected_delivery_date?->format('d/m/Y') ?? '—' }}</td>
                                <td class="py-xs text-right">
                                    @if($order->status === 'recue')
                                        <span class="text-brand-emerald font-bold">Reçu</span>
                                    @else
                                        <span class="text-accent-yellow font-bold">{{ ucfirst($order->status) }}</span>
                                    @endif
                                </td>
                            </tr>
                        @empty
                            <tr><td colspan="4" class="py-md text-center text-outline">Aucun bon de commande pour ce fournisseur.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            @endif
        </div>
    </div>

    <x-modal name="modal-regularisation-fournisseur" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Enregistrer un Règlement</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-regularisation-fournisseur' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <div class="bg-surface-zebra rounded-lg p-md text-xs mb-md">
            <div class="flex justify-between"><span class="text-outline">Solde global dû</span><span class="font-bold text-error-deep">{{ number_format($this->soldeGlobal, 0, ',', ' ') }} FCFA</span></div>
        </div>
        <div class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Montant du Règlement (FCFA)</label>
                <input wire:model="regularisationMontant" type="number" placeholder="Saisir le montant..." class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('regularisationMontant') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('regularisationMontant') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Compte de Trésorerie</label>
                <select wire:model="regularisationTreasuryId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('regularisationTreasuryId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->treasuryAccounts as $account)
                        <option value="{{ $account->id }}">{{ $account->label }}</option>
                    @endforeach
                </select>
                @error('regularisationTreasuryId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
        </div>
        <button type="button" wire:click="confirmRegularisation" class="w-full mt-md py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">Valider le Règlement</button>
    </x-modal>
</div>
