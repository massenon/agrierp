<div class="mt-md space-y-md">
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">assignment_return</span>{{ __('ventes.titre_retours_avoirs') }}
            </h2>
            <p class="text-xs text-outline mt-xs">{{ __('ventes.desc_retours_avoirs') }}</p>
        </div>
        <button type="button" wire:click="newReturn" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
            <span class="material-symbols-outlined text-[18px]">add_circle</span>{{ __('ventes.btn_nouveau_retour') }}
        </button>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-md">
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-info-blue shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_retours_mois') }}</span><span class="material-symbols-outlined text-[18px] text-info-blue">assignment_return</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ $this->kpis['retours_mois'] }}</span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-accent-yellow shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_montant_avoirs') }}</span><span class="material-symbols-outlined text-[18px] text-brand-forest">payments</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['montant_avoirs'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-emerald shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_produits_retournes') }}</span><span class="material-symbols-outlined text-[18px] text-brand-emerald">inventory_2</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ $this->kpis['produits_retournes'] }}</span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-error-red shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_taux_retour') }}</span><span class="material-symbols-outlined text-[18px] text-error-red">percent</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['taux_retour'], 1, ',', ' ') }}%</span>
        </div>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_avoir') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_facture') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_client') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_date') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_motif') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_decision') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_montant') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_statut') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->creditNotes as $i => $note)
                        <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="{{ __('ventes.col_avoir') }}" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $note->credit_note_number }}</td>
                            <td data-label="{{ __('ventes.col_facture') }}" class="px-md py-sm text-xs font-mono">{{ strtoupper(substr($note->sale_id, 0, 8)) }}</td>
                            <td data-label="{{ __('ventes.col_client') }}" class="px-md py-sm text-xs">{{ $note->sale?->customer?->name ?? __('ventes.client_anonyme') }}</td>
                            <td data-label="{{ __('ventes.col_date') }}" class="px-md py-sm text-xs">{{ $note->created_at->format('d/m/Y') }}</td>
                            <td data-label="{{ __('ventes.col_motif') }}" class="px-md py-sm text-xs">{{ $note->reason }}</td>
                            <td data-label="{{ __('ventes.col_decision') }}" class="px-md py-sm text-xs">
                                @if($note->decision === 'reintegre')
                                    <span class="inline-flex items-center gap-1 text-brand-emerald font-bold"><span class="material-symbols-outlined text-[14px]">restart_alt</span>{{ __('ventes.decision_reintegre') }}</span>
                                @elseif($note->decision === 'reforme')
                                    <span class="inline-flex items-center gap-1 text-error-deep font-bold"><span class="material-symbols-outlined text-[14px]">heart_broken</span>{{ __('ventes.decision_reforme') }}</span>
                                @else
                                    —
                                @endif
                            </td>
                            <td data-label="{{ __('ventes.col_montant') }}" class="px-md py-sm text-xs text-right font-bold">{{ number_format($note->amount, 0, ',', ' ') }}</td>
                            <td data-label="{{ __('ventes.col_statut') }}" class="px-md py-sm">
                                @if($note->status === 'traite')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">{{ __('ventes.statut_traite') }}</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">{{ __('ventes.statut_en_attente') }}</span>
                                @endif
                                {{-- MECEF-1 — facture d'avoir (FA) : seulement quand la facture d'origine est normalisée. --}}
                                @if($note->mecef_status)
                                    <p class="text-[10px] text-outline mt-xs">{{ __('ventes.info_mecef_avoir_prefixe') }} {{ \App\Support\MecefEtat::libelle($note->mecef_status) }}@if($note->mecef_status !== 'transmise' && $note->mecef_message) — {{ $note->mecef_message }}@endif</p>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                @if($note->mecef_status && $note->mecef_status !== 'transmise')
                                    <button type="button" wire:click="retryMecef('{{ $note->id }}')" class="text-error-deep hover:text-red-800 p-1" title="Retransmettre au MeCeF"><span class="material-symbols-outlined text-[18px]">refresh</span></button>
                                @endif
                                @if($note->status === 'en_attente')
                                    <button type="button" wire:click="markAsTreated('{{ $note->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="{{ __('ventes.statut_traite') }}"><span class="material-symbols-outlined text-[18px]">check_circle</span></button>
                                @endif
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="9" class="px-md py-lg text-center text-outline">{{ __('ventes.msg_aucun_retour') }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-nouveau-retour" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ __('ventes.titre_nouveau_retour') }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-nouveau-retour' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveReturn" class="space-y-md">
            <div>
                <p class="text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_facture_source') }}</p>
                <select wire:model.live="saleId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('saleId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">{{ __('ventes.select_selectionner_vente') }}</option>
                    @foreach($this->recentSales as $sale)
                        <option value="{{ $sale->id }}">{{ strtoupper(substr($sale->id, 0, 8)) }} — {{ $sale->customer?->name ?? __('ventes.client_anonyme') }} — {{ number_format($sale->total, 0, ',', ' ') }} FCFA</option>
                    @endforeach
                </select>
                @error('saleId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            @if($this->selectedSale)
                <div>
                    <p class="text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_article_retourne') }}</p>
                    <select wire:model.live="productId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('productId') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">{{ __('ventes.select_selectionner') }}</option>
                        @foreach($this->selectedSale->lines as $line)
                            <option value="{{ $line->product_id }}">{{ $line->product?->name }} ({{ rtrim(rtrim(number_format($line->qty, 2, '.', ''), '0'), '.') }} {{ $line->product?->unit }})</option>
                        @endforeach
                    </select>
                    @error('productId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>

                <div class="grid grid-cols-2 gap-sm">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_qte_retournee') }}</label>
                        <input wire:model="qty" type="number" min="0.01" step="0.01" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('qty') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('qty') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_montant_avoir') }}</label>
                        <input wire:model="amount" type="number" min="0" class="w-full h-11 px-md border rounded-lg text-sm font-bold {{ $errors->has('amount') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('amount') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                </div>

                <div>
                    <p class="text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_motif_retour') }}</p>
                    <input wire:model="reason" type="text" placeholder="ex : Produit détérioré, erreur de quantité, mortalité..." class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('reason') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('reason') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>

                <div>
                    <p class="text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_inspection_sanitaire') }}</p>
                    <textarea wire:model="inspectionNotes" rows="2" placeholder="ex : Contrôle visuel effectué, RAS" class="w-full px-md py-sm border border-outline-variant rounded-lg text-sm"></textarea>
                </div>

                <div>
                    <p class="text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_decision') }}</p>
                    <div class="flex gap-md">
                        <label class="flex items-center gap-xs cursor-pointer">
                            <input wire:model="decision" type="radio" value="reintegre" class="text-brand-emerald">
                            <span class="text-sm flex items-center gap-1"><span class="material-symbols-outlined text-[16px] text-brand-emerald">restart_alt</span>{{ __('ventes.btn_reintegrer_stock') }}</span>
                        </label>
                        <label class="flex items-center gap-xs cursor-pointer">
                            <input wire:model="decision" type="radio" value="reforme" class="text-error-deep">
                            <span class="text-sm flex items-center gap-1"><span class="material-symbols-outlined text-[16px] text-error-deep">heart_broken</span>{{ __('ventes.btn_reformer') }}</span>
                        </label>
                    </div>
                    <p class="text-[10px] text-outline mt-xs">{{ __('ventes.aide_decision_retour') }}</p>
                </div>
            @endif

            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-nouveau-retour' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('ventes.btn_annuler') }}</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ __('ventes.btn_enregistrer_retour') }}</button>
            </div>
        </form>
    </x-modal>
</div>
