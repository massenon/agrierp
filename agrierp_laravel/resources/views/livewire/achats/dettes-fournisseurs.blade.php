<div class="mt-md space-y-md">
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">account_balance_wallet</span>Dettes Fournisseurs
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Suivi des sommes dues aux fournisseurs et de leurs échéances.</p>
        </div>
        <div class="flex items-center gap-xs">
            <button type="button" wire:click="exportDettesFournisseursPdf" wire:loading.attr="disabled" wire:target="exportDettesFournisseursPdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
            </button>
            <button type="button" wire:click="openPaymentModal" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                <span class="material-symbols-outlined text-[18px]">add_circle</span>Enregistrer un Règlement
            </button>
        </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <x-kpi-card label="Dettes totales" icon="payments" color="emerald" :value="number_format($this->kpis['dettes_totales'], 0, ',', ' ').' FCFA'" />
        <x-kpi-card label="En retard" icon="warning" color="red" :value="number_format($this->kpis['en_retard'], 0, ',', ' ').' FCFA'" />
        <x-kpi-card label="Fournisseurs concernés" icon="local_shipping" color="blue" :value="$this->kpis['fournisseurs_concernes']" />
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md flex flex-col md:flex-row items-stretch md:items-center justify-between gap-sm border-b border-outline-variant">
            <div class="relative flex-1 md:max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
            </div>
            <select wire:model.live="statusFilter" class="border border-outline-variant rounded-lg text-xs px-sm py-2 bg-white w-full md:w-auto">
                <option value="">Tous les statuts</option>
                <option value="A echoir">À échoir</option>
                <option value="En retard">En retard</option>
                <option value="Regle">Réglé</option>
            </select>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Fournisseur</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Montant Dû</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Échéance</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->debts as $i => $debt)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Fournisseur" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $debt->supplier?->name }}</td>
                            <td data-label="Montant Dû" class="px-md py-sm text-xs">{{ number_format($debt->balance, 0, ',', ' ') }}</td>
                            <td data-label="Échéance" class="px-md py-sm text-xs">{{ $debt->due_date?->format('d/m/Y') ?? '—' }}</td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($debt->display_status === 'soldee')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Réglé</span>
                                @elseif($debt->display_status === 'en_retard')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-bg text-error-deep border-error-deep/30">En retard</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-blue-100 text-info-blue border-blue-300">À échoir</span>
                                @endif
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="4" class="px-md py-lg text-center text-outline">Aucune dette fournisseur pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-create-dettes-fournisseurs" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Enregistrer un Règlement</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-dettes-fournisseurs' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="submitPaiementFournisseur" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Fournisseur *</label>
                <select wire:model="paymentSupplierId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('paymentSupplierId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->suppliers as $supplier)
                        <option value="{{ $supplier->id }}">{{ $supplier->name }}</option>
                    @endforeach
                </select>
                @error('paymentSupplierId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Montant réglé (FCFA) *</label>
                <input wire:model="paymentAmount" type="number" placeholder="ex : 185000" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('paymentAmount') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('paymentAmount') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date de règlement *</label>
                <input wire:model="paymentDate" type="date" @if($this->dateMinSaisie) min="{{ $this->dateMinSaisie }}" @endif class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('paymentDate') ? 'is-invalid' : 'border-outline-variant' }}">
                {{-- Ticket EX6 — exercice clos ou absent : le motif R4 sous « Date » (EF6), comme la dépense. --}}
                @error('paymentDate') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Compte de Trésorerie *</label>
                <select wire:model="paymentTreasuryAccountId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('paymentTreasuryAccountId') ? 'is-invalid' : 'border-outline-variant' }}">
                    @foreach($this->treasuryAccounts as $account)
                        <option value="{{ $account->id }}">{{ $account->label }} ({{ number_format($account->balance, 0, ',', ' ') }} FCFA)</option>
                    @endforeach
                </select>
                @error('paymentTreasuryAccountId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                <p class="text-[10px] text-outline mt-xs">Le règlement est appliqué en priorité aux dettes les plus anciennes de ce fournisseur.</p>
            </div>
            <div class="flex justify-end gap-sm pt-md border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-dettes-fournisseurs' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>
</div>
