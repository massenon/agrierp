<div class="mt-md">
    <div class="mb-md">
        <select wire:model.live="lotFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">{{ __('rapports.elevage_filtre_lot') }}</option>
            @foreach($this->lots as $lot)
                <option value="{{ $lot->id }}">{{ $lot->code }}</option>
            @endforeach
        </select>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-md mb-md">
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-emerald shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">{{ __('rapports.elevage_kpi_production') }}</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ number_format($this->kpis['production_totale'], 0, ',', ' ') }}</span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-info-blue shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">{{ __('rapports.elevage_kpi_ponte') }}</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ $this->kpis['taux_ponte_moyen'] !== null ? $this->kpis['taux_ponte_moyen'].' %' : '—' }}</span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-error-red shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">{{ __('rapports.elevage_kpi_mortalite') }}</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ $this->kpis['taux_mortalite_hebdo'] !== null ? $this->kpis['taux_mortalite_hebdo'].' %' : '—' }}</span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-accent-yellow shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">{{ __('rapports.elevage_kpi_ca') }}</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ number_format($this->kpis['ca_ventes'], 0, ',', ' ') }} <span class="text-xs font-normal text-outline">FCFA</span></span>
        </div>
    </div>

    <div class="flex items-center gap-xs mb-md overflow-x-auto">
        <button type="button" wire:click="$set('activeTable', 't1')" class="px-md py-2 rounded-full text-xs font-bold whitespace-nowrap flex-shrink-0 {{ $activeTable === 't1' ? 'bg-brand-emerald text-white' : 'border border-outline-variant text-outline' }}">{{ __('rapports.elevage_btn_t1') }}</button>
        <button type="button" wire:click="$set('activeTable', 't2')" class="px-md py-2 rounded-full text-xs font-bold whitespace-nowrap flex-shrink-0 {{ $activeTable === 't2' ? 'bg-brand-emerald text-white' : 'border border-outline-variant text-outline' }}">{{ __('rapports.elevage_btn_t2') }}</button>
        <button type="button" wire:click="$set('activeTable', 't3')" class="px-md py-2 rounded-full text-xs font-bold whitespace-nowrap flex-shrink-0 {{ $activeTable === 't3' ? 'bg-brand-emerald text-white' : 'border border-outline-variant text-outline' }}">{{ __('rapports.elevage_btn_t3') }}</button>
    </div>

    @if($activeTable === 't1')
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <p class="text-[10px] text-outline px-md py-sm border-b border-outline-variant italic">{{ __('rapports.elevage_t1_note') }}</p>
            <div class="overflow-x-auto">
                <table class="w-full text-xs">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="sticky left-0 bg-surface-zebra z-10 px-sm py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t1_col_date') }}</th>
                            <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t1_col_lot') }}</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase">{{ __('rapports.elevage_t1_col_effectif_m') }}</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t1_col_effectif_f') }}</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase">{{ __('rapports.elevage_t1_col_sous_meres') }}</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t1_col_sevres') }}</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase">{{ __('rapports.elevage_t1_col_achats') }}</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t1_col_nes') }}</th>
                            <th class="px-sm py-sm text-center text-[10px] text-error-deep font-bold uppercase">{{ __('rapports.elevage_t1_col_morts') }}</th>
                            <th class="px-sm py-sm text-center text-[10px] text-brand-emerald font-bold uppercase">{{ __('rapports.elevage_t1_col_effectif_final') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($this->entries as $i => $e)
                            <tr class="{{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} border-b border-outline-variant">
                                <td class="sticky left-0 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} z-10 px-sm py-sm font-bold text-brand-forest border-r border-outline-variant">{{ $e->entry_date->format('d/m/Y') }}</td>
                                <td class="px-sm py-sm font-bold text-brand-emerald border-r border-outline-variant">{{ $e->lot?->code }}</td>
                                <td class="px-sm py-sm text-center">{{ $e->effectif_m }}</td>
                                <td class="px-sm py-sm text-center border-r border-outline-variant">{{ $e->effectif_f }}</td>
                                <td class="px-sm py-sm text-center">{{ $e->effectif_smeres }}</td>
                                <td class="px-sm py-sm text-center border-r border-outline-variant">{{ $e->effectif_sevres }}</td>
                                <td class="px-sm py-sm text-center">{{ $e->achat }}</td>
                                <td class="px-sm py-sm text-center border-r border-outline-variant">{{ $e->ne }}</td>
                                <td class="px-sm py-sm text-center text-error-deep font-bold">{{ $e->mort }}</td>
                                <td class="px-sm py-sm text-center font-bold text-brand-emerald">{{ $e->effectif_final }}</td>
                            </tr>
                        @empty
                            <tr><td colspan="10" class="px-md py-lg text-center text-outline">{{ __('rapports.elevage_t1_vide') }}</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
            <p class="text-[10px] text-outline px-md py-sm border-t border-outline-variant">{{ __('rapports.elevage_t1_formule') }}</p>
        </div>
    @endif

    @if($activeTable === 't2')
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <div class="overflow-x-auto">
                <table class="w-full text-xs">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="sticky left-0 bg-surface-zebra z-10 px-sm py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t2_col_date') }}</th>
                            <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t2_col_lot') }}</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase">{{ __('rapports.elevage_t2_col_sexe_vendu') }}</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase">{{ __('rapports.elevage_t2_col_qte_vendue') }}</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t2_col_montant_vente') }}</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t2_col_effectif_final') }}</th>
                            <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('rapports.elevage_t2_col_traitement') }}</th>
                            <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t2_col_dose') }}</th>
                            <th class="px-sm py-sm text-left text-[10px] text-error-deep font-bold uppercase">{{ __('rapports.elevage_t2_col_signes') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($this->entries as $i => $e)
                            <tr class="{{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} border-b border-outline-variant">
                                <td class="sticky left-0 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} z-10 px-sm py-sm font-bold text-brand-forest border-r border-outline-variant">{{ $e->entry_date->format('d/m/Y') }}</td>
                                <td class="px-sm py-sm font-bold text-brand-emerald border-r border-outline-variant">{{ $e->lot?->code }}</td>
                                <td class="px-sm py-sm text-center">{{ $e->vente_sexe ?? '—' }}</td>
                                <td class="px-sm py-sm text-center">{{ $e->vente }}</td>
                                <td class="px-sm py-sm text-right font-bold border-r border-outline-variant">{{ number_format($e->vente_montant, 0, ',', ' ') }}</td>
                                <td class="px-sm py-sm text-center font-bold text-brand-emerald border-r border-outline-variant">{{ $e->effectif_final }}</td>
                                <td class="px-sm py-sm">{{ $e->treatmentProduct?->name ?? '—' }}</td>
                                <td class="px-sm py-sm border-r border-outline-variant">{{ $e->treatment_dose ?? '—' }}</td>
                                <td class="px-sm py-sm text-outline">{{ $e->symptomes ?: 'RAS' }}</td>
                            </tr>
                        @empty
                            <tr><td colspan="9" class="px-md py-lg text-center text-outline">{{ __('rapports.elevage_t2_vide') }}</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
            <p class="text-[10px] text-outline px-md py-sm border-t border-outline-variant">{{ __('rapports.elevage_t2_formule') }}</p>
        </div>
    @endif

    @if($activeTable === 't3')
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <p class="text-[10px] text-outline px-md py-sm border-b border-outline-variant italic">{{ __('rapports.elevage_t3_note') }}</p>
            <div class="overflow-x-auto">
                <table class="w-full text-xs">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="sticky left-0 bg-surface-zebra z-10 px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t3_col_age') }}</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t3_col_jour') }}</th>
                            <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t3_col_lot') }}</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('rapports.elevage_t3_col_or') }}</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t3_col_taux_ponte') }}</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('rapports.elevage_t3_col_casses') }}</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t3_col_commercialisables') }}</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('rapports.elevage_t3_col_srh') }}</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase border-r border-outline-variant">{{ __('rapports.elevage_t3_col_ts') }}</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('rapports.elevage_t3_col_os') }}</th>
                            <th class="px-sm py-sm text-right text-[10px] text-brand-emerald font-bold uppercase">{{ __('rapports.elevage_t3_col_stock_final') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($this->entries->where('ponte_total', '>', 0) as $i => $e)
                            <tr class="{{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} border-b border-outline-variant">
                                <td class="sticky left-0 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} z-10 px-sm py-sm text-center font-bold text-brand-forest border-r border-outline-variant">{{ $e->lot?->created_date ? intdiv($e->lot->created_date->diffInDays($e->entry_date), 7) : '—' }}</td>
                                <td class="px-sm py-sm text-center border-r border-outline-variant">{{ $e->entry_date->format('d/m/Y') }}</td>
                                <td class="px-sm py-sm font-bold text-brand-emerald border-r border-outline-variant">{{ $e->lot?->code }}</td>
                                <td class="px-sm py-sm text-right font-bold text-brand-emerald">{{ $e->ponte_total }}</td>
                                <td class="px-sm py-sm text-right font-bold border-r border-outline-variant">{{ $e->effectif_final > 0 ? number_format(($e->ponte_total / $e->effectif_final) * 100, 1) : '—' }} %</td>
                                <td class="px-sm py-sm text-right text-error-deep">{{ $e->ponte_casses }}</td>
                                <td class="px-sm py-sm text-right font-bold border-r border-outline-variant">{{ $e->ponte_total - $e->ponte_casses }}</td>
                                @php($l = $this->ledgerOeufs[$e->entry_date->format('Y-m-d')] ?? null)
                                <td class="px-sm py-sm text-right">{{ $l ? number_format($l['srh'], 0, ',', ' ') : '—' }}</td>
                                <td class="px-sm py-sm text-right font-bold border-r border-outline-variant">{{ $l ? number_format($l['ts'], 0, ',', ' ') : '—' }}</td>
                                <td class="px-sm py-sm text-right">{{ $l ? number_format($l['os'], 0, ',', ' ') : '—' }}</td>
                                <td class="px-sm py-sm text-right font-bold text-brand-emerald">{{ $l ? number_format($l['final'], 0, ',', ' ').' plateaux'.($l['vrac'] > 0 ? ' + '.$l['vrac'].' vrac' : '') : '—' }}</td>
                            </tr>
                        @empty
                            <tr><td colspan="11" class="px-md py-lg text-center text-outline">{{ __('rapports.elevage_t3_vide') }}</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
            <p class="text-[10px] text-outline px-md py-sm border-t border-outline-variant">{{ __('rapports.elevage_t3_formule') }}</p>
        </div>
    @endif
</div>
