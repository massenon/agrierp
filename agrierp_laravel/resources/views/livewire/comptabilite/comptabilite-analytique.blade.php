<div>
    <div class="border-b border-outline-variant pb-md mb-lg flex flex-col sm:flex-row sm:items-center sm:justify-between gap-sm">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">insights</span>Comptabilité Analytique
            </h2>
            <p class="text-xs text-outline mt-xs">Marges réelles par espèce/filière — croisement des charges (Classe 6) et produits (Classe 7).</p>
        </div>
        <button type="button" wire:click="exportComptaAnalytiquePdf" wire:loading.attr="disabled" wire:target="exportComptaAnalytiquePdf" class="flex items-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
        </button>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-lg flex flex-wrap items-center gap-sm">
        <input wire:model.live="startDate" type="date" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
        <span class="text-xs text-outline">au</span>
        <input wire:model.live="endDate" type="date" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
        <select wire:model.live="filiereFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">Filière : Toutes</option>
            @foreach($this->filieres as $f)
                <option value="{{ $f->label }}">{{ $f->label }}</option>
            @endforeach
        </select>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md mb-lg">
        <x-kpi-card label="Chiffre d'Affaires Analytique" icon="payments" color="emerald" :value="number_format($this->kpis['ca'], 0, ',', ' ').' F'" />
        <x-kpi-card label="Charges Directes" icon="trending_down" color="red" :value="number_format($this->kpis['charges'], 0, ',', ' ').' F'" />
        <x-kpi-card label="Marge Brute Opérationnelle" icon="trending_up" color="emerald" :value="number_format($this->kpis['marge'], 0, ',', ' ').' F'" />
        <x-kpi-card label="Taux de Rentabilité" icon="percent" color="maize" :value="$this->kpis['taux'] !== null ? $this->kpis['taux'].' %' : '—'" />
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-[65%_35%] gap-md">
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
            <h3 class="text-sm font-bold text-brand-forest mb-md">Chiffre d'Affaires vs Coûts Directs par Filière</h3>
            @php
                $rows = $this->rows;
                $maxVal = max(1, $rows->max(fn($r) => max($r['ca'], $r['charges'])));
                $barWidth = 40; $gap = 30; $chartHeight = 160; $svgWidth = max(420, $rows->count() * ($barWidth * 2 + $gap) + 40);
            @endphp
            <svg viewBox="0 0 {{ $svgWidth }} 220" class="w-full">
                @foreach($rows as $i => $row)
                    @php
                        $x = 20 + $i * ($barWidth * 2 + $gap);
                        $caHeight = $row['ca'] > 0 ? ($row['ca'] / $maxVal) * $chartHeight : 0;
                        $chargesHeight = $row['charges'] > 0 ? ($row['charges'] / $maxVal) * $chartHeight : 0;
                    @endphp
                    <rect x="{{ $x }}" y="{{ 180 - $caHeight }}" width="{{ $barWidth }}" height="{{ $caHeight }}" fill="#065f46" rx="2" />
                    <rect x="{{ $x + $barWidth }}" y="{{ 180 - $chargesHeight }}" width="{{ $barWidth }}" height="{{ $chargesHeight }}" fill="#FFD55F" rx="2" />
                    <text x="{{ $x + $barWidth }}" y="198" font-size="10" fill="#6f7973" text-anchor="middle">{{ Str::limit($row['filiere']->label, 12) }}</text>
                @endforeach
            </svg>
            <div class="flex items-center gap-lg mt-sm text-xs">
                <span class="flex items-center gap-xs text-outline"><span class="w-3 h-3 rounded-full bg-brand-emerald inline-block"></span>Chiffre d'affaires</span>
                <span class="flex items-center gap-xs text-outline"><span class="w-3 h-3 rounded-full bg-accent-yellow inline-block"></span>Coûts directs</span>
            </div>
        </div>
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
            <h3 class="text-sm font-bold text-brand-forest mb-md">Top 3 Charges (Filière Sélectionnée)</h3>
            @if($this->selectedTopCharges === null)
                <p class="text-xs text-outline">Sélectionnez une filière pour voir le détail des charges principales.</p>
            @elseif($this->selectedTopCharges->isEmpty())
                <p class="text-xs text-outline">Aucune charge directe sur cette filière pour la période sélectionnée.</p>
            @else
                <div class="space-y-sm">
                    @foreach($this->selectedTopCharges as $charge)
                        <div class="flex justify-between text-xs border-b border-outline-variant/50 pb-1">
                            <span class="text-outline">{{ $charge['code'] }} - {{ $charge['label'] }}</span>
                            <span class="font-bold">{{ number_format($charge['amount'], 0, ',', ' ') }} FCFA</span>
                        </div>
                    @endforeach
                </div>
            @endif
        </div>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden mt-lg">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Filière</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">CA (FCFA)</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Charges (FCFA)</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Marge (FCFA)</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Taux</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->rows as $i => $row)
                        <tr class="border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td class="px-md py-sm text-xs font-bold text-brand-forest">{{ $row['filiere']->label }}</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($row['ca'], 0, ',', ' ') }}</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($row['charges'], 0, ',', ' ') }}</td>
                            <td class="px-md py-sm text-xs text-right font-bold {{ $row['marge'] >= 0 ? 'text-brand-emerald' : 'text-error-deep' }}">{{ number_format($row['marge'], 0, ',', ' ') }}</td>
                            <td class="px-md py-sm text-xs text-right">{{ $row['taux'] !== null ? $row['taux'].' %' : '—' }}</td>
                        </tr>
                    @empty
                        <tr><td colspan="5" class="px-md py-lg text-center text-outline">Aucune filière active.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
</div>
