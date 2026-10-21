<div class="mt-md space-y-md">
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">assignment_return</span>Retours et Avoirs
            </h2>
            <p class="text-xs text-outline mt-xs">Gestion des retours produits, avoirs clients et inspection sanitaire du cheptel retourné.</p>
        </div>
        <button type="button" wire:click="newReturn" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
            <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouveau Retour
        </button>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-md">
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-info-blue shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Retours du mois</span><span class="material-symbols-outlined text-[18px] text-info-blue">assignment_return</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ $this->kpis['retours_mois'] }}</span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-accent-yellow shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Montant Avoirs</span><span class="material-symbols-outlined text-[18px] text-brand-forest">payments</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['montant_avoirs'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-emerald shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Produits Retournés</span><span class="material-symbols-outlined text-[18px] text-brand-emerald">inventory_2</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ $this->kpis['produits_retournes'] }}</span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-error-red shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Taux de Retour</span><span class="material-symbols-outlined text-[18px] text-error-red">percent</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['taux_retour'], 1, ',', ' ') }}%</span>
        </div>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Avoir</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Facture</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Client</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Motif</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Décision</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Montant</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->creditNotes as $i => $note)
                        <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Avoir" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $note->credit_note_number }}</td>
                            <td data-label="Facture" class="px-md py-sm text-xs font-mono">{{ strtoupper(substr($note->sale_id, 0, 8)) }}</td>
                            <td data-label="Client" class="px-md py-sm text-xs">{{ $note->sale?->customer?->name ?? 'Client Anonyme' }}</td>
                            <td data-label="Date" class="px-md py-sm text-xs">{{ $note->created_at->format('d/m/Y') }}</td>
                            <td data-label="Motif" class="px-md py-sm text-xs">{{ $note->reason }}</td>
                            <td data-label="Décision" class="px-md py-sm text-xs">
                                @if($note->decision === 'reintegre')
                                    <span class="inline-flex items-center gap-1 text-brand-emerald font-bold"><span class="material-symbols-outlined text-[14px]">restart_alt</span>Réintégré</span>
                                @elseif($note->decision === 'reforme')
                                    <span class="inline-flex items-center gap-1 text-error-deep font-bold"><span class="material-symbols-outlined text-[14px]">heart_broken</span>Réforme</span>
                                @else
                                    —
                                @endif
                            </td>
                            <td data-label="Montant" class="px-md py-sm text-xs text-right font-bold">{{ number_format($note->amount, 0, ',', ' ') }}</td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($note->status === 'traite')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Traité</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">En attente</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                @if($note->status === 'en_attente')
                                    <button type="button" wire:click="markAsTreated('{{ $note->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="Marquer comme traité"><span class="material-symbols-outlined text-[18px]">check_circle</span></button>
                                @endif
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="9" class="px-md py-lg text-center text-outline">Aucun retour pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-nouveau-retour" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Nouveau Retour</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-nouveau-retour' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveReturn" class="space-y-md">
            <div>
                <p class="text-[10px] text-brand-forest font-bold uppercase mb-xs">1. Facture Source</p>
                <select wire:model.live="saleId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('saleId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner une vente --</option>
                    @foreach($this->recentSales as $sale)
                        <option value="{{ $sale->id }}">{{ strtoupper(substr($sale->id, 0, 8)) }} — {{ $sale->customer?->name ?? 'Client Anonyme' }} — {{ number_format($sale->total, 0, ',', ' ') }} FCFA</option>
                    @endforeach
                </select>
                @error('saleId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            @if($this->selectedSale)
                <div>
                    <p class="text-[10px] text-brand-forest font-bold uppercase mb-xs">2. Article Retourné</p>
                    <select wire:model.live="productId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('productId') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">-- Sélectionner --</option>
                        @foreach($this->selectedSale->lines as $line)
                            <option value="{{ $line->product_id }}">{{ $line->product?->name }} ({{ rtrim(rtrim(number_format($line->qty, 2, '.', ''), '0'), '.') }} {{ $line->product?->unit }})</option>
                        @endforeach
                    </select>
                    @error('productId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>

                <div class="grid grid-cols-2 gap-sm">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Quantité Retournée *</label>
                        <input wire:model="qty" type="number" min="0.01" step="0.01" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('qty') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('qty') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Montant de l'Avoir (FCFA) *</label>
                        <input wire:model="amount" type="number" min="0" class="w-full h-11 px-md border rounded-lg text-sm font-bold {{ $errors->has('amount') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('amount') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                </div>

                <div>
                    <p class="text-[10px] text-brand-forest font-bold uppercase mb-xs">3. Motif du Retour</p>
                    <input wire:model="reason" type="text" placeholder="ex : Produit détérioré, erreur de quantité, mortalité..." class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('reason') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('reason') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>

                <div>
                    <p class="text-[10px] text-brand-forest font-bold uppercase mb-xs">4. Inspection Sanitaire (si sujet vivant)</p>
                    <textarea wire:model="inspectionNotes" rows="2" placeholder="ex : Contrôle visuel effectué, RAS" class="w-full px-md py-sm border border-outline-variant rounded-lg text-sm"></textarea>
                </div>

                <div>
                    <p class="text-[10px] text-brand-forest font-bold uppercase mb-xs">5. Décision</p>
                    <div class="flex gap-md">
                        <label class="flex items-center gap-xs cursor-pointer">
                            <input wire:model="decision" type="radio" value="reintegre" class="text-brand-emerald">
                            <span class="text-sm flex items-center gap-1"><span class="material-symbols-outlined text-[16px] text-brand-emerald">restart_alt</span>Réintégrer au stock</span>
                        </label>
                        <label class="flex items-center gap-xs cursor-pointer">
                            <input wire:model="decision" type="radio" value="reforme" class="text-error-deep">
                            <span class="text-sm flex items-center gap-1"><span class="material-symbols-outlined text-[16px] text-error-deep">heart_broken</span>Réformer (détruire)</span>
                        </label>
                    </div>
                    <p class="text-[10px] text-outline mt-xs">Réintégrer ajoute réellement la quantité au stock du produit. Réformer n'a aucun impact sur le stock (traçabilité seule).</p>
                </div>
            @endif

            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-nouveau-retour' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer le Retour</button>
            </div>
        </form>
    </x-modal>
</div>
