<div>
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm mb-md">
        <div>
            <h2 class="text-lg lg:text-xl font-bold flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald">account_balance_wallet</span>Rentabilité de Lot</h2>
            <p class="text-xs text-outline mt-xs">Coûts, revenus et rentabilité réelle par bande — alimenté automatiquement par les achats, ventes et charges imputés à chaque lot.</p>
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
            <p class="text-sm font-semibold text-on-surface mt-sm">Aucune bande pour le moment.</p>
            <a href="{{ route('elevage.bandes') }}" class="text-xs font-bold text-brand-emerald mt-sm inline-block">Créer une bande depuis Bandes &amp; Sujets →</a>
        </div>
    @else
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-md mb-lg">
            <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-info-blue shadow-sm">
                <span class="text-[10px] text-outline font-bold uppercase">Coût Total Connu du Lot</span>
                <span class="text-xl font-extrabold block mt-xs">{{ number_format($this->coutTotalConnu, 0, ',', ' ') }} FCFA</span>
                <p class="text-[9px] text-outline mt-xs">Hors main d'œuvre (clé d'imputation à arbitrer)</p>
            </div>
            <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-emerald shadow-sm">
                <span class="text-[10px] text-outline font-bold uppercase">Revenu Total du Lot</span>
                <span class="text-xl font-extrabold block mt-xs">{{ number_format($this->revenuTotalConnu, 0, ',', ' ') }} FCFA</span>
                <p class="text-[9px] text-outline mt-xs">Ventes validées, nettes des avoirs traités</p>
            </div>
            <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-accent-yellow shadow-sm">
                <span class="text-[10px] text-outline font-bold uppercase">Marge Nette</span>
                <span class="text-xl font-extrabold block mt-xs {{ $this->margeNette >= 0 ? 'text-brand-emerald' : 'text-error-deep' }}">{{ number_format($this->margeNette, 0, ',', ' ') }} FCFA</span>
                <p class="text-[9px] text-outline mt-xs">Sur revenus et coûts connus</p>
            </div>
            <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-error-red shadow-sm">
                <span class="text-[10px] text-outline font-bold uppercase">Coût de Revient / Sujet</span>
                <span class="text-xl font-extrabold block mt-xs">{{ $this->coutParSujet !== null ? number_format($this->coutParSujet, 0, ',', ' ').' FCFA' : '—' }}</span>
                <p class="text-[9px] text-outline mt-xs">Sur coûts connus ÷ effectif initial</p>
            </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-md mb-lg">
            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-lg">
                <h3 class="text-sm font-bold text-on-surface mb-md flex items-center gap-xs"><span class="material-symbols-outlined text-error-deep text-[18px]">trending_down</span>Détail des Coûts</h3>
                <div class="space-y-sm">
                    @foreach($this->couts as $cout)
                        <div class="flex justify-between items-center text-xs border-b border-outline-variant/50 pb-xs">
                            <span class="text-outline">{{ $cout['label'] }}</span>
                            @if($cout['reel'])
                                <span class="font-bold text-brand-forest">{{ number_format($cout['montant'], 0, ',', ' ') }} FCFA</span>
                            @else
                                <span class="text-outline italic text-[10px] text-right max-w-[60%]" title="{{ $cout['motif'] ?? '' }}">{{ $cout['motif'] ?? 'En attente' }}</span>
                            @endif
                        </div>
                    @endforeach
                    <div class="flex justify-between items-center text-sm pt-xs font-bold text-brand-forest">
                        <span>Total connu</span>
                        <span>{{ number_format($this->coutTotalConnu, 0, ',', ' ') }} FCFA</span>
                    </div>
                </div>
            </div>
            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-lg">
                <h3 class="text-sm font-bold text-on-surface mb-md flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">trending_up</span>Détail des Revenus</h3>
                <div class="space-y-sm">
                    @forelse($this->revenus as $revenu)
                        <div class="flex justify-between items-center text-xs border-b border-outline-variant/50 pb-xs">
                            <span class="text-outline">{{ $revenu['label'] }}</span>
                            @if($revenu['reel'])
                                <span class="font-bold text-brand-emerald">{{ number_format($revenu['montant'], 0, ',', ' ') }} FCFA</span>
                            @else
                                <span class="text-outline italic text-[10px] text-right max-w-[60%]" title="{{ $revenu['motif'] ?? '' }}">{{ $revenu['motif'] ?? 'En attente' }}</span>
                            @endif
                        </div>
                    @empty
                        <p class="text-xs text-outline italic">Aucune vente encore enregistrée sur cette bande.</p>
                    @endforelse
                    <div class="flex justify-between items-center text-sm pt-xs font-bold text-brand-emerald">
                        <span>Total connu</span>
                        <span>{{ number_format($this->revenuTotalConnu, 0, ',', ' ') }} FCFA</span>
                    </div>
                </div>
            </div>
        </div>

        <div class="rounded-lg p-md text-sm font-semibold flex items-start gap-sm bg-info-blue/10 border border-info-blue/20 text-brand-forest">
            <span class="material-symbols-outlined text-[18px]">info</span>
            <span>Marge Nette calculée sur revenus et coûts connus. La main d'œuvre reste hors du calcul tant qu'aucune clé d'imputation aux bandes n'est arbitrée.</span>
        </div>

        <div class="mt-md bg-info-blue/10 border border-info-blue/20 rounded-lg p-md text-xs text-brand-forest">
            <span class="material-symbols-outlined text-[16px] align-middle mr-xs">info</span>
            Ce bilan agrège automatiquement : le coût d'acquisition initial de la bande, les provendes servies (valorisées au prix indicatif du catalogue Types de Provende), les frais vétérinaires imputés au lot, et les ventes enregistrées via le POS — sujets vifs, œufs et produits transformés compris, imputés à la bande désignée à la caisse, jamais répartis par une heuristique.
        </div>
    @endif
</div>
