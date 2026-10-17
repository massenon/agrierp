<div>
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">balance</span>Bilan Simplifié de l'Entreprise
            </h2>
            <p class="text-xs text-outline mt-xs">Situation patrimoniale de la Ferme École OLOUWACHEGOUN au {{ \Carbon\Carbon::parse($asOfDate)->format('d/m/Y') }}.</p>
        </div>
        <div class="flex items-center gap-xs">
            <input wire:model.live="asOfDate" type="date" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
        </div>
    </div>

    <div class="mb-lg">
        @if($this->bilan['is_balanced'])
            <div class="bg-brand-emerald/10 border border-brand-emerald/30 rounded-lg p-md flex items-center gap-xs text-brand-forest text-sm font-bold">
                <span class="material-symbols-outlined text-brand-emerald">check_circle</span>Bilan équilibré — Total Actif = Total Passif = {{ number_format($this->bilan['total_actif'], 0, ',', ' ') }} FCFA
            </div>
        @else
            <div class="bg-error-bg border border-error-deep/30 rounded-lg p-md flex items-center gap-xs text-error-deep text-sm font-bold">
                <span class="material-symbols-outlined text-error-red">error</span>Déséquilibre détecté — Actif {{ number_format($this->bilan['total_actif'], 0, ',', ' ') }} FCFA ≠ Passif {{ number_format($this->bilan['total_passif'], 0, ',', ' ') }} FCFA
            </div>
        @endif
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-md">
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <div class="px-md py-sm border-b-2 border-brand-emerald bg-brand-emerald/5"><h3 class="text-sm font-bold text-brand-emerald uppercase">Actif (Emplois)</h3></div>
            <div class="p-md space-y-md text-xs">
                <div>
                    <p class="font-bold text-brand-forest uppercase text-[10px] mb-xs">Actif Immobilisé (Classe 2)</p>
                    @forelse($this->bilan['immo'] as $line)
                        <div class="flex justify-between py-1 border-b border-outline-variant"><span class="text-outline">{{ $line['code'] }} - {{ $line['label'] }}</span><span>{{ number_format($line['balance'], 0, ',', ' ') }}</span></div>
                    @empty
                        <p class="text-outline italic py-1">Aucune écriture sur cette classe pour l'instant.</p>
                    @endforelse
                    <div class="flex justify-between py-1 font-bold text-brand-forest"><span>Sous-total Immobilisé</span><span>{{ number_format($this->bilan['total_immo'], 0, ',', ' ') }}</span></div>
                </div>
                <div>
                    <p class="font-bold text-brand-forest uppercase text-[10px] mb-xs">Actif Circulant (Classes 3 &amp; 4)</p>
                    @forelse($this->bilan['stocks'] as $line)
                        <div class="flex justify-between py-1 border-b border-outline-variant"><span class="text-outline">{{ $line['code'] }} - {{ $line['label'] }}</span><span>{{ number_format($line['balance'], 0, ',', ' ') }}</span></div>
                    @empty
                    @endforelse
                    @forelse($this->bilan['creances'] as $line)
                        <div class="flex justify-between py-1 border-b border-outline-variant"><span class="text-outline">{{ $line['code'] }} - {{ $line['label'] }}</span><span>{{ number_format($line['balance'], 0, ',', ' ') }}</span></div>
                    @empty
                    @endforelse
                    @if(empty($this->bilan['stocks']) && empty($this->bilan['creances']))
                        <p class="text-outline italic py-1">Aucune écriture sur ces classes pour l'instant.</p>
                    @endif
                    <div class="flex justify-between py-1 font-bold text-brand-forest"><span>Sous-total Circulant</span><span>{{ number_format($this->bilan['total_circulant'], 0, ',', ' ') }}</span></div>
                </div>
                <div>
                    <p class="font-bold text-brand-forest uppercase text-[10px] mb-xs">Trésorerie Actif (Classe 5)</p>
                    @forelse($this->bilan['tresorerie'] as $line)
                        <div class="flex justify-between py-1 border-b border-outline-variant"><span class="text-outline">{{ $line['code'] }} - {{ $line['label'] }}</span><span>{{ number_format($line['balance'], 0, ',', ' ') }}</span></div>
                    @empty
                        <p class="text-outline italic py-1">Aucune écriture sur cette classe pour l'instant.</p>
                    @endforelse
                    <div class="flex justify-between py-1 font-bold text-brand-forest"><span>Sous-total Trésorerie</span><span>{{ number_format($this->bilan['total_tresorerie'], 0, ',', ' ') }}</span></div>
                </div>
            </div>
            <div class="px-md py-md border-t-2 border-brand-forest bg-surface-zebra flex justify-between items-center">
                <span class="font-black text-brand-forest uppercase text-sm">Total Actif</span>
                <span class="font-black text-brand-emerald text-lg">{{ number_format($this->bilan['total_actif'], 0, ',', ' ') }}</span>
            </div>
        </div>

        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <div class="px-md py-sm border-b-2 border-info-blue bg-info-blue/5"><h3 class="text-sm font-bold text-info-blue uppercase">Passif (Ressources)</h3></div>
            <div class="p-md space-y-md text-xs">
                <div>
                    <p class="font-bold text-brand-forest uppercase text-[10px] mb-xs">Capitaux Propres (Classe 1)</p>
                    @forelse($this->bilan['capitaux'] as $line)
                        <div class="flex justify-between py-1 border-b border-outline-variant"><span class="text-outline">{{ $line['code'] }} - {{ $line['label'] }}</span><span>{{ number_format(-$line['balance'], 0, ',', ' ') }}</span></div>
                    @empty
                        <p class="text-outline italic py-1">Aucune écriture sur cette classe pour l'instant.</p>
                    @endforelse
                    <div class="flex justify-between py-1 border-b border-outline-variant"><span class="text-outline">Résultat de l'exercice</span><span class="{{ $this->bilan['resultat'] >= 0 ? 'text-brand-emerald' : 'text-error-deep' }} font-bold">{{ number_format($this->bilan['resultat'], 0, ',', ' ') }}</span></div>
                    <div class="flex justify-between py-1 font-bold text-brand-forest"><span>Sous-total Capitaux Propres</span><span>{{ number_format($this->bilan['total_capitaux'] + $this->bilan['resultat'], 0, ',', ' ') }}</span></div>
                </div>
                <div>
                    <p class="font-bold text-brand-forest uppercase text-[10px] mb-xs">Dettes (Classe 4)</p>
                    @forelse($this->bilan['dettes'] as $line)
                        <div class="flex justify-between py-1 border-b border-outline-variant"><span class="text-outline">{{ $line['code'] }} - {{ $line['label'] }}</span><span>{{ number_format($line['balance'], 0, ',', ' ') }}</span></div>
                    @empty
                        <p class="text-outline italic py-1">Aucune écriture sur cette classe pour l'instant.</p>
                    @endforelse
                    <div class="flex justify-between py-1 font-bold text-brand-forest"><span>Sous-total Dettes</span><span>{{ number_format($this->bilan['total_dettes'], 0, ',', ' ') }}</span></div>
                </div>
                <div class="pt-lg text-outline italic text-[10px] border-t border-outline-variant">
                    <p>Le passif reflète les ressources ayant financé les emplois inscrits à l'actif : capitaux propres de l'exploitant et dettes envers les tiers. Calculé directement depuis le grand livre comptable.</p>
                </div>
            </div>
            <div class="px-md py-md border-t-2 border-brand-forest bg-surface-zebra flex justify-between items-center">
                <span class="font-black text-brand-forest uppercase text-sm">Total Passif</span>
                <span class="font-black text-info-blue text-lg">{{ number_format($this->bilan['total_passif'], 0, ',', ' ') }}</span>
            </div>
        </div>
    </div>
</div>
