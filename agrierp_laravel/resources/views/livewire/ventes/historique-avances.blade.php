<div class="mt-md space-y-md">
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">savings</span>{{ __('ventes.titre_historique_avances') }}
            </h2>
            <p class="text-xs text-outline mt-xs">{{ __('ventes.desc_historique_avances') }}</p>
        </div>
        <div class="flex flex-wrap items-center gap-xs">
            <button type="button" wire:click="exportAvancesPdf" wire:loading.attr="disabled" wire:target="exportAvancesPdf" class="flex items-center gap-xs bg-white border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50"><span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>{{ __('ventes.btn_exporter') }}</button>
            @can('manage-ventes')
            <button type="button" wire:click="newAdvance" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                <span class="material-symbols-outlined text-[18px]">add_circle</span>{{ __('ventes.btn_nouvelle_avance') }}
            </button>
            @endcan
        </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-3 gap-md">
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-accent-yellow shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_avances_en_cours') }}</span><span class="material-symbols-outlined text-[18px] text-brand-forest">savings</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['avances_en_cours'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-info-blue shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_clients_concernes') }}</span><span class="material-symbols-outlined text-[18px] text-info-blue">groups</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ $this->kpis['clients_concernes'] }}</span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-emerald shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_avances_soldees_mois') }}</span><span class="material-symbols-outlined text-[18px] text-brand-emerald">task_alt</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ $this->kpis['avances_soldees_mois'] }}</span>
        </div>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md flex flex-wrap items-center gap-sm">
        <div class="relative flex-1 min-w-[180px]">
            <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
            <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher un client..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
        </div>
        <select wire:model.live="statusFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">{{ __('ventes.filtre_tous_statuts') }}</option>
            <option value="En cours">{{ __('ventes.statut_en_cours') }}</option>
            <option value="Soldée">{{ __('ventes.statut_soldee') }}</option>
        </select>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_client') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_montant_avance') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_solde_restant') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_date') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_statut') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->advances as $i => $advance)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="{{ __('ventes.col_client') }}" class="px-md py-sm text-xs"><a wire:navigate href="{{ route('ventes.profile-client', $advance->customer) }}" class="text-brand-forest hover:text-brand-emerald hover:underline font-bold">{{ $advance->customer?->name }}</a></td>
                            <td data-label="{{ __('ventes.col_montant_avance') }}" class="px-md py-sm text-xs text-right">{{ number_format($advance->amount, 0, ',', ' ') }} FCFA</td>
                            <td data-label="{{ __('ventes.col_solde_restant') }}" class="px-md py-sm text-xs text-right font-bold {{ $advance->remaining > 0 ? 'text-brand-emerald' : 'text-outline' }}">{{ number_format($advance->remaining, 0, ',', ' ') }} FCFA</td>
                            <td data-label="{{ __('ventes.col_date') }}" class="px-md py-sm text-xs">{{ $advance->advance_date->format('d/m/Y') }}</td>
                            <td data-label="{{ __('ventes.col_statut') }}" class="px-md py-sm">
                                @if($advance->remaining > 0)
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">{{ __('ventes.statut_en_cours') }}</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">{{ __('ventes.statut_soldee') }}</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                @can('manage-ventes')
                                <button type="button" wire:click="editAdvance('{{ $advance->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="{{ __('ventes.titre_modifier_avance') }}"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                @if($advance->remaining > 0)
                                    <button type="button" wire:click="openImputationModal('{{ $advance->id }}')" class="text-brand-forest hover:text-brand-emerald p-1" title="{{ __('ventes.titre_imputer_avance') }}"><span class="material-symbols-outlined text-[18px]">sync</span></button>
                                @endif
                                <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-avance-{{ $advance->id }}' })" class="text-outline hover:text-error-deep p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">archive</span></button>
                                @endcan
                            </td>
                        </tr>
                        <x-modal-confirm-delete :name="'archive-avance-'.$advance->id" :item-label="$advance->customer?->name.' — '.number_format($advance->amount, 0, ',', ' ').' FCFA'" :action="'archiveAdvance(\''.$advance->id.'\')'" />
                    @empty
                        <tr><td colspan="6" class="px-md py-lg text-center text-outline">{{ __('ventes.msg_aucune_avance') }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-create-avance" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingAdvanceId ? __('ventes.titre_modifier_avance') : __('ventes.titre_nouvelle_avance') }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-avance' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveAdvance" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_client_requis') }}</label>
                <select wire:model="customerId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('customerId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">{{ __('ventes.select_selectionner') }}</option>
                    @foreach($this->customers as $customer)
                        <option value="{{ $customer->id }}">{{ $customer->name }}</option>
                    @endforeach
                </select>
                @error('customerId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            @php($avanceFigee = $this->editingAdvance && ($this->editingAdvance->estEntamee() || $this->editingAdvance->estComptabilisee()))
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_montant_requis') }}</label>
                <input wire:model="amount" type="number" @disabled($avanceFigee) class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('amount') ? 'is-invalid' : 'border-outline-variant' }} {{ $avanceFigee ? 'bg-surface-zebra text-outline' : '' }}">
                @error('amount') <p class="invalid-feedback">{{ $message }}</p> @enderror
                @if($avanceFigee)
                    <p class="text-[10px] text-outline mt-xs">{{ __('ventes.info_avance_figee') }}</p>
                @endif
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_date_requis') }}</label>
                <input wire:model="advanceDate" type="date" @if($this->dateMinSaisie) min="{{ $this->dateMinSaisie }}" @endif class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('advanceDate') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('advanceDate') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            @if(! $editingAdvanceId)
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_compte_tresorerie_requis') }}</label>
                    <select wire:model="treasuryAccountId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('treasuryAccountId') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">{{ __('ventes.select_selectionner') }}</option>
                        @foreach($this->treasuryAccounts as $compte)
                            <option value="{{ $compte->id }}">{{ $compte->label }}</option>
                        @endforeach
                    </select>
                    @error('treasuryAccountId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_mode_paiement') }}</label>
                    <select wire:model="paymentMode" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('paymentMode') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">{{ __('ventes.select_non_precise') }}</option>
                        <option value="especes">{{ __('ventes.mode_especes') }}</option>
                        <option value="mobile_money">{{ __('ventes.mode_mobile_money') }}</option>
                        <option value="virement">{{ __('ventes.mode_virement_court') }}</option>
                        <option value="cheque">{{ __('ventes.mode_cheque') }}</option>
                    </select>
                    @error('paymentMode') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_motif_commande') }}</label>
                    <input wire:model="motif" type="text" maxlength="255" placeholder="ex : Réservation 50 poussins d'un jour" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('motif') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('motif') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
            @endif
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-avance' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('ventes.btn_annuler') }}</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ __('ventes.btn_enregistrer') }}</button>
            </div>
        </form>
    </x-modal>

    <x-modal name="modal-imputation" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ __('ventes.titre_imputer_avance') }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-imputation' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <div class="bg-surface-zebra rounded-lg p-md text-xs mb-md">
            <div class="flex justify-between"><span class="text-outline">{{ __('ventes.label_solde_disponible_avance') }}</span><span class="font-bold text-brand-emerald">{{ number_format($imputationMax, 0, ',', ' ') }} FCFA</span></div>
        </div>
        <div class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_creance_a_regler') }}</label>
                <select wire:model="imputationReceivableId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('imputationReceivableId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">{{ __('ventes.select_selectionner') }}</option>
                    @foreach($this->imputationReceivables as $receivable)
                        <option value="{{ $receivable->id }}">{{ strtoupper(substr($receivable->sale_id ?? $receivable->id, 0, 8)) }} — Solde {{ number_format($receivable->balance, 0, ',', ' ') }} FCFA</option>
                    @endforeach
                </select>
                @error('imputationReceivableId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                @if($this->imputationReceivables->isEmpty())
                    <p class="text-[10px] text-outline mt-xs">{{ __('ventes.info_pas_creance') }}</p>
                @endif
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_montant_imputer') }}</label>
                <input wire:model="imputationMontant" type="number" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('imputationMontant') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('imputationMontant') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
        </div>
        <button type="button" wire:click="confirmImputation" class="w-full mt-md py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">{{ __('ventes.btn_valider_imputation') }}</button>
    </x-modal>
</div>
