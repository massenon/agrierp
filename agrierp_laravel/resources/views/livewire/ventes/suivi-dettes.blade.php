<div class="mt-md space-y-md">
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">request_quote</span>{{ __('ventes.titre_suivi_dettes') }}
            </h2>
            <p class="text-xs text-outline mt-xs">{{ __('ventes.desc_suivi_dettes') }}</p>
        </div>
        @can('manage-ventes')
        <button type="button" onclick="document.getElementById('debt-quick-target').scrollIntoView()" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
            <span class="material-symbols-outlined text-[18px]">add_circle</span>{{ __('ventes.btn_ajouter_recouvrement') }}
        </button>
        @endcan
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-error-red shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_encours_global') }}</span><span class="material-symbols-outlined text-[18px] text-error-red">payments</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['encours_global'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
            <p class="text-[10px] text-outline mt-xs">Total dû par les clients</p>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-accent-yellow shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_echus_30j') }}</span><span class="material-symbols-outlined text-[18px] text-brand-forest">event_busy</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['echus_30j'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
            <p class="text-[10px] text-outline mt-xs">À recouvrer d'urgence</p>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-emerald shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_taux_recouvrement') }}</span><span class="material-symbols-outlined text-[18px] text-brand-emerald">trending_up</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ $this->kpis['taux_recouvrement'] }}%</span>
            <p class="text-[10px] text-outline mt-xs">Factures créées ce mois-ci</p>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-forest shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_acomptes_recus') }}</span><span class="material-symbols-outlined text-[18px] text-brand-forest">savings</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['acomptes_recus'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
            <p class="text-[10px] text-outline mt-xs">Avances sur commandes (mois)</p>
        </div>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md flex flex-wrap items-center gap-sm">
        <div class="relative flex-1 min-w-[180px]">
            <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
            <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher par nom de débiteur..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
        </div>
        <select wire:model.live="ancienneteFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">{{ __('ventes.filtre_anciennete_toutes') }}</option>
            <option value="saine">{{ __('ventes.filtre_saines') }}</option>
            <option value="retard">{{ __('ventes.filtre_en_retard') }}</option>
            <option value="litige">{{ __('ventes.filtre_litigieuses') }}</option>
        </select>
        <button type="button" wire:click="exportCreancesPdf" wire:loading.attr="disabled" wire:target="exportCreancesPdf" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>{{ __('ventes.btn_exporter_pdf') }}
        </button>
    </div>

    <div id="debt-quick-target" class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_debiteur') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_facture_associee') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_echeance') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_total_facture') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_solde_restant') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->debts as $i => $debt)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="{{ __('ventes.col_debiteur') }}" class="px-md py-sm text-xs"><a wire:navigate href="{{ route('ventes.profile-client', $debt->customer) }}" class="text-brand-forest hover:text-brand-emerald hover:underline font-bold">{{ $debt->customer?->name }}</a></td>
                            <td data-label="{{ __('ventes.col_facture') }}" class="px-md py-sm text-xs font-mono">{{ strtoupper(substr($debt->sale_id ?? $debt->id, 0, 8)) }}</td>
                            <td data-label="{{ __('ventes.col_echeance') }}" class="px-md py-sm text-xs">{{ $debt->due_date?->format('d/m/Y') ?? '—' }} @if($debt->days_overdue > 0)<span class="text-error-deep font-bold">({{ $debt->days_overdue }}j)</span>@endif</td>
                            <td data-label="{{ __('ventes.col_total_facture') }}" class="px-md py-sm text-xs text-right">{{ number_format($debt->amount, 0, ',', ' ') }} FCFA</td>
                            <td data-label="{{ __('ventes.col_solde_restant') }}" class="px-md py-sm text-xs text-right font-bold text-error-deep">{{ number_format($debt->balance, 0, ',', ' ') }} FCFA</td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                @can('manage-ventes')
                                <button type="button" wire:click="openPaymentModal('{{ $debt->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="{{ __('ventes.titre_enregistrer_recouvrement') }}"><span class="material-symbols-outlined text-[18px]">credit_card</span></button>
                                <button type="button" wire:click="sendReminder('{{ $debt->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Relancer"><span class="material-symbols-outlined text-[18px]">chat</span></button>
                                @endcan
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="6" class="px-md py-lg text-center text-outline">{{ __('ventes.msg_aucune_creance') }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-add-payment" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ __('ventes.titre_enregistrer_recouvrement') }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-add-payment' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <div class="bg-surface-zebra rounded-lg p-md text-xs mb-md">
            <div class="flex justify-between"><span class="text-outline">{{ __('ventes.label_debiteur_facture') }}</span><span class="font-bold">{{ $paymentTargetLabel }}</span></div>
            <div class="flex justify-between"><span class="text-outline">{{ __('ventes.label_solde_restant_modal') }}</span><span class="font-bold text-error-deep">{{ number_format($paymentSolde, 0, ',', ' ') }} FCFA</span></div>
        </div>
        <div class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_montant_reglement') }}</label>
                <input wire:model="paymentMontant" type="number" placeholder="Saisir le montant..." class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('paymentMontant') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('paymentMontant') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_compte_tresorerie') }}</label>
                <select wire:model="paymentTreasuryId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('paymentTreasuryId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">{{ __('ventes.select_selectionner') }}</option>
                    @foreach($this->treasuryAccounts as $account)
                        <option value="{{ $account->id }}">{{ $account->label }}</option>
                    @endforeach
                </select>
                @error('paymentTreasuryId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
        </div>
        <button type="button" wire:click="confirmPayment" class="w-full mt-md py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">{{ __('ventes.btn_valider_reglement') }}</button>
    </x-modal>
</div>
