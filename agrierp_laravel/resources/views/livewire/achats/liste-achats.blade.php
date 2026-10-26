<div class="mt-md space-y-md">
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">list_alt</span>Liste d'Achats
            </h2>
            <p class="text-xs text-outline mt-xs">Grand livre d'achats et d'approvisionnements de marchandises.</p>
        </div>
        <div class="flex flex-wrap items-center gap-xs">
            <input wire:model.live="dateFilter" type="date" min="{{ \App\Support\ExerciceChoisi::bornes()[0] }}" max="{{ \App\Support\ExerciceChoisi::bornes()[1] }}" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <button type="button" wire:click="exportAchatsPdf" wire:loading.attr="disabled" wire:target="exportAchatsPdf" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full disabled:opacity-50"><span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF</button>
            <button @lectureSeule type="button" wire:click="openRefundModal" class="flex items-center gap-xs bg-white border border-outline-variant hover:bg-surface-zebra text-error-deep font-bold text-xs px-md py-sm rounded-full"><span class="material-symbols-outlined text-[18px]">payments</span>Ajouter Remboursement</button>
        </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-emerald shadow-sm"><div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Dépenses Totales</span><span class="material-symbols-outlined text-[18px] text-brand-emerald">payments</span></div><span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ number_format($this->kpis['depenses_totales'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span></div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-info-blue shadow-sm"><div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Achats Réglés</span><span class="material-symbols-outlined text-[18px] text-info-blue">task_alt</span></div><span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ $this->kpis['achats_regles'] }}</span></div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-error-red shadow-sm"><div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Dettes en Cours</span><span class="material-symbols-outlined text-[18px] text-error-red">warning</span></div><span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ number_format($this->kpis['dettes_en_cours'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span></div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-accent-yellow shadow-sm"><div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Écarts / Retours</span><span class="material-symbols-outlined text-[18px] text-brand-forest">assignment_return</span></div><span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ $this->kpis['ecarts_retours'] }}</span></div>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md flex flex-wrap items-center gap-sm">
        <div class="relative flex-1 min-w-[180px]">
            <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
            <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher par référence ou fournisseur..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
        </div>
        <select wire:model.live="statusFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">Tous les règlements</option>
            <option value="paye">Payé entièrement</option>
            <option value="dette">Dette fournisseur</option>
        </select>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Référence Achat</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Fournisseur</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Catégorie</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Montant Payé</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Montant Total</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Dette</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->purchases as $i => $purchase)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Référence" class="px-md py-sm text-xs"><button type="button" wire:click="view('{{ $purchase->id }}')" class="text-brand-emerald hover:underline font-bold font-mono">{{ strtoupper(substr($purchase->id, 0, 8)) }}</button></td>
                            <td data-label="Date" class="px-md py-sm text-xs">{{ $purchase->purchase_date->format('d/m/Y') }}</td>
                            <td data-label="Fournisseur" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $purchase->supplier?->name }}</td>
                            <td data-label="Catégorie" class="px-md py-sm text-xs">{{ $purchase->categorie }}</td>
                            @php $dette = $purchase->payable ? max(0, $purchase->payable->balance) : 0; @endphp
                            <td data-label="Montant Payé" class="px-md py-sm text-xs text-right font-bold">{{ number_format($purchase->total - $dette, 0, ',', ' ') }} FCFA</td>
                            <td data-label="Montant Total" class="px-md py-sm text-xs text-right font-bold">{{ number_format($purchase->total, 0, ',', ' ') }} FCFA</td>
                            <td data-label="Dette" class="px-md py-sm text-xs text-right font-bold {{ $dette > 0 ? 'text-error-deep' : '' }}">{{ $dette > 0 ? number_format($dette, 0, ',', ' ').' FCFA' : '0' }}</td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($purchase->returned_at)
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-surface-zebra text-outline border-outline-variant">RETOURNÉ</span>
                                @elseif($purchase->is_dette)
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-bg text-error-deep border-error-deep/30">DETTE FOURNISSEUR</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">PAYÉ ENTIÈREMENT</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button" wire:click="view('{{ $purchase->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Voir"><span class="material-symbols-outlined text-[18px]">visibility</span></button>
                                @unless($purchase->returned_at)
                                    <button @lectureSeule type="button" wire:click="openReturnModal('{{ $purchase->id }}')" class="text-error-deep hover:text-red-800 p-1" title="Retour fournisseur"><span class="material-symbols-outlined text-[18px]">cancel</span></button>
                                @endunless
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="9" class="px-md py-lg text-center text-outline">Aucun achat pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <x-pagination :paginator="$this->purchases" />
    </div>

    <x-modal name="modal-return-purchase" max-width="md">
        <div class="flex items-center gap-md text-error-deep border-b border-outline-variant pb-md mb-md">
            <span class="material-symbols-outlined" style="font-size:36px;">warning</span>
            <div><h3 class="font-bold text-lg">Retour Fournisseur</h3><p class="text-xs text-outline">Contrôle de validation d'annulation d'achat</p></div>
        </div>
        <div class="p-md bg-error-bg border border-error-deep/20 rounded-lg text-error-deep text-xs mb-md">
            ATTENTION : Cette action est définitive. Vous êtes sur le point d'annuler cet achat. Cette action décrémentera automatiquement les stocks d'approvisionnement de l'entrepôt local.
        </div>
        <label class="block text-xs text-outline font-bold mb-xs">MOTIF DE L'ANNULATION / RETOUR</label>
        <select wire:model="returnReason" class="w-full h-11 px-md border rounded-lg text-sm bg-white mb-md {{ $errors->has('returnReason') ? 'is-invalid' : 'border-outline-variant' }}">
            <option value="">Sélectionner un motif...</option>
            <option>Marchandises endommagées / périmées</option>
            <option>Erreur de saisie / d'article</option>
            <option>Non-conformité technique à la livraison</option>
        </select>
        @error('returnReason') <p class="invalid-feedback">{{ $message }}</p> @enderror
        <div class="flex justify-end gap-sm pt-md border-t border-outline-variant">
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-return-purchase' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
            <button @lectureSeule type="button" wire:click="confirmReturnPurchase" class="px-md py-sm rounded-lg bg-error-red text-white text-sm font-bold hover:bg-red-800">Confirmer le Retour</button>
        </div>
    </x-modal>

    <x-modal name="modal-ajouter-remboursement" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Ajouter un Remboursement</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-ajouter-remboursement' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="submitRefund" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Fournisseur *</label>
                <select wire:model="refundSupplierId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('refundSupplierId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->suppliers as $supplier)
                        <option value="{{ $supplier->id }}">{{ $supplier->name }}</option>
                    @endforeach
                </select>
                @error('refundSupplierId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Montant Remboursé (FCFA) *</label>
                <input wire:model="refundAmount" type="number" min="1" placeholder="ex : 50000" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('refundAmount') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('refundAmount') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date du Remboursement *</label>
                <input wire:model="refundDate" type="date" @if($this->dateMinSaisie) min="{{ $this->dateMinSaisie }}" @endif class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Compte de Trésorerie</label>
                <select wire:model="refundTreasuryAccountId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('refundTreasuryAccountId') ? 'is-invalid' : 'border-outline-variant' }}">
                    @foreach($this->treasuryAccounts as $account)
                        <option value="{{ $account->id }}">{{ $account->label }}</option>
                    @endforeach
                </select>
                @error('refundTreasuryAccountId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-ajouter-remboursement' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button @lectureSeule type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>

    @if($this->viewingPurchase)
        <div x-data x-on:keydown.escape.window="$wire.closeDrawer()" class="fixed inset-0 bg-black/40 z-[105]" wire:click="closeDrawer"></div>
        <div class="fixed top-0 right-0 h-full w-full sm:w-96 bg-white z-[106] shadow-2xl overflow-y-auto">
            <div class="flex items-center justify-between px-lg py-md border-b border-outline-variant bg-brand-forest">
                <span class="text-white font-bold text-sm font-mono">{{ strtoupper(substr($this->viewingPurchase->id, 0, 8)) }}</span>
                <button type="button" wire:click="closeDrawer" class="text-white/80 hover:text-white"><span class="material-symbols-outlined">close</span></button>
            </div>
            <div class="p-lg space-y-md">
                <div class="grid grid-cols-2 gap-sm text-xs">
                    <div><span class="text-outline block">Fournisseur</span><span class="font-bold">{{ $this->viewingPurchase->supplier?->name }}</span></div>
                    <div><span class="text-outline block">Date</span><span class="font-bold">{{ $this->viewingPurchase->purchase_date->format('d/m/Y') }}</span></div>
                </div>
                <div class="border-t border-outline-variant pt-md">
                    <p class="text-xs font-bold text-brand-forest uppercase mb-sm">Articles</p>
                    <div class="space-y-xs">
                        @foreach($this->viewingPurchase->lines as $line)
                            <div class="flex justify-between text-xs border-b border-outline-variant/50 pb-1">
                                <span>{{ $line->product?->name }} × {{ rtrim(rtrim(number_format($line->qty, 2, '.', ''), '0'), '.') }}</span>
                                <span class="font-bold">{{ number_format($line->qty * $line->unit_price, 0, ',', ' ') }} FCFA</span>
                            </div>
                        @endforeach
                    </div>
                </div>
                <div class="border-t border-outline-variant pt-md flex justify-between font-bold text-brand-emerald text-sm">
                    <span>Total</span><span>{{ number_format($this->viewingPurchase->total, 0, ',', ' ') }} FCFA</span>
                </div>
                @if($this->viewingPurchase->payable && $this->viewingPurchase->payable->status !== 'soldee')
                    <div class="bg-error-bg border border-error-deep/20 rounded-lg p-sm text-xs text-error-deep">
                        Solde restant dû : <strong>{{ number_format($this->viewingPurchase->payable->balance, 0, ',', ' ') }} FCFA</strong>
                    </div>
                @endif
            </div>
        </div>
    @endif
</div>
