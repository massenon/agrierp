<div>
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm mb-md">
        <div>
            <h2 class="text-lg lg:text-xl font-bold flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald">account_balance_wallet</span>{{ __('elevage.titre_rentabilite_lot') }}</h2>
            <p class="text-xs text-outline mt-xs">{{ __('elevage.desc_rentabilite_lot') }}</p>
        </div>
        @if($this->lots->isNotEmpty())
            <select wire:model.live="lotId" class="h-11 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold">
                @foreach($this->lots as $lot)
                    <option value="{{ $lot->id }}">{{ $lot->code }} ({{ $lot->species?->label }})</option>
                @endforeach
            </select>
        @endif
    </div>

    @if(!$this->selectedLot)
        <div class="bg-white border border-outline-variant rounded-lg p-lg text-center">
            <span class="material-symbols-outlined text-outline-variant text-[44px]">inbox</span>
            <p class="text-sm font-semibold text-on-surface mt-sm">{{ __('elevage.msg_aucune_bande_bilan') }}</p>
            <a wire:navigate href="{{ route('elevage.bandes') }}" class="text-xs font-bold text-brand-emerald mt-sm inline-block">{{ __('elevage.lien_creer_bande') }}</a>
        </div>
    @else
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-md mb-lg">
            <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-info-blue shadow-sm">
                <span class="text-[10px] text-outline font-bold uppercase">{{ __('elevage.kpi_cout_total_lot') }}</span>
                <span class="text-xl font-extrabold block mt-xs">{{ number_format($this->coutTotalConnu, 0, ',', ' ') }} FCFA</span>
                <p class="text-[9px] text-outline mt-xs">{{ __('elevage.kpi_cout_total_lot_desc') }}</p>
            </div>
            <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-emerald shadow-sm">
                <span class="text-[10px] text-outline font-bold uppercase">{{ __('elevage.kpi_revenu_total_lot') }}</span>
                <span class="text-xl font-extrabold block mt-xs">{{ number_format($this->revenuTotalConnu, 0, ',', ' ') }} FCFA</span>
                <p class="text-[9px] text-outline mt-xs">{{ __('elevage.kpi_revenu_total_lot_desc') }}</p>
            </div>
            <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-accent-yellow shadow-sm">
                <span class="text-[10px] text-outline font-bold uppercase">{{ __('elevage.kpi_marge_nette') }}</span>
                <span class="text-xl font-extrabold block mt-xs {{ $this->margeNette >= 0 ? 'text-brand-emerald' : 'text-error-deep' }}">{{ number_format($this->margeNette, 0, ',', ' ') }} FCFA</span>
                <p class="text-[9px] text-outline mt-xs">{{ __('elevage.kpi_marge_nette_desc') }}</p>
            </div>
            <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-error-red shadow-sm">
                <span class="text-[10px] text-outline font-bold uppercase">{{ __('elevage.kpi_cout_revient_sujet') }}</span>
                <span class="text-xl font-extrabold block mt-xs">{{ $this->coutParSujet !== null ? number_format($this->coutParSujet, 0, ',', ' ').' FCFA' : '—' }}</span>
                <p class="text-[9px] text-outline mt-xs">{{ __('elevage.kpi_cout_revient_sujet_desc') }}</p>
            </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-md mb-lg">
            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-lg">
                <h3 class="text-sm font-bold text-on-surface mb-md flex items-center gap-xs"><span class="material-symbols-outlined text-error-deep text-[18px]">trending_down</span>{{ __('elevage.titre_detail_couts') }}</h3>
                <div class="space-y-sm">
                    @foreach($this->couts as $cout)
                        <div class="flex justify-between items-center text-xs border-b border-outline-variant/50 pb-xs">
                            <span class="text-outline">{{ $cout['label'] }}</span>
                            @if($cout['reel'])
                                <span class="font-bold text-brand-forest">{{ number_format($cout['montant'], 0, ',', ' ') }} FCFA</span>
                            @else
                                <span class="text-outline italic text-[10px] text-right max-w-[60%]" title="{{ $cout['motif'] ?? '' }}">{{ $cout['motif'] ?? __('elevage.bilan_en_attente') }}</span>
                            @endif
                        </div>
                    @endforeach
                    <div class="flex justify-between items-center text-sm pt-xs font-bold text-brand-forest">
                        <span>{{ __('elevage.label_total_connu') }}</span>
                        <span>{{ number_format($this->coutTotalConnu, 0, ',', ' ') }} FCFA</span>
                    </div>
                </div>
            </div>
            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-lg">
                <h3 class="text-sm font-bold text-on-surface mb-md flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">trending_up</span>{{ __('elevage.titre_detail_revenus') }}</h3>
                <div class="space-y-sm">
                    @forelse($this->revenus as $revenu)
                        <div class="flex justify-between items-center text-xs border-b border-outline-variant/50 pb-xs">
                            <span class="text-outline">{{ $revenu['label'] }}</span>
                            @if($revenu['reel'])
                                <span class="font-bold text-brand-emerald">{{ number_format($revenu['montant'], 0, ',', ' ') }} FCFA</span>
                            @else
                                <span class="text-outline italic text-[10px] text-right max-w-[60%]" title="{{ $revenu['motif'] ?? '' }}">{{ $revenu['motif'] ?? __('elevage.bilan_en_attente') }}</span>
                            @endif
                        </div>
                    @empty
                        <p class="text-xs text-outline italic">{{ __('elevage.msg_aucune_vente_bande') }}</p>
                    @endforelse
                    <div class="flex justify-between items-center text-sm pt-xs font-bold text-brand-emerald">
                        <span>{{ __('elevage.label_total_connu') }}</span>
                        <span>{{ number_format($this->revenuTotalConnu, 0, ',', ' ') }} FCFA</span>
                    </div>
                </div>
            </div>
        </div>

        <div class="rounded-lg p-md text-sm font-semibold flex items-start gap-sm bg-info-blue/10 border border-info-blue/20 text-brand-forest">
            <span class="material-symbols-outlined text-[18px]">info</span>
            <span>{{ __('elevage.info_marge_nette') }}</span>
        </div>

        <div class="mt-md bg-info-blue/10 border border-info-blue/20 rounded-lg p-md text-xs text-brand-forest">
            <span class="material-symbols-outlined text-[16px] align-middle mr-xs">info</span>
            {{ __('elevage.info_bilan_agregation') }}
        </div>
    @endif
</div>
