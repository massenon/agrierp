<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">balance</span>Balance Générale
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Synthèse des soldes de tous les comptes utilisés — vérification de l'équilibre avant clôture.</p>
        </div>
        <button type="button" wire:click="exportBalancePdf" wire:loading.attr="disabled" wire:target="exportBalancePdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
        </button>
    </div>

    <x-anouveaux-provisoires :ouverture="$this->balance['ouverture']" />

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-lg flex flex-wrap items-center gap-sm">
        <label for="bal-periode-select" class="text-[10px] text-brand-forest font-bold uppercase">Période :</label>
        <select id="bal-periode-select" wire:model.live="periode" class="text-sm font-bold border border-outline-variant rounded-lg px-md py-2 bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
            <option value="mois">{{ ucfirst(now()->translatedFormat('F Y')) }} (période courante)</option>
            <option value="exercice">Exercice complet — {{ $this->fiscalYear?->year ?? now()->year }}</option>
        </select>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-3 gap-md mb-lg">
        <div class="bg-white p-md rounded-lg border border-outline-variant border-l-4 border-l-brand-emerald shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">Total Débits (Soldes Finaux)</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ number_format($this->balance['total_final_debit'], 0, ',', ' ') }} F</span>
        </div>
        <div class="bg-white p-md rounded-lg border border-outline-variant border-l-4 border-l-error-red shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">Total Crédits (Soldes Finaux)</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ number_format($this->balance['total_final_credit'], 0, ',', ' ') }} F</span>
        </div>
        <div class="p-md rounded-lg border shadow-sm {{ $this->balance['is_balanced'] ? 'border-brand-emerald/30 bg-brand-emerald/5' : 'border-error-red/30 bg-error-red/10' }}">
            <span class="text-[10px] text-outline font-bold uppercase block">Écart (doit être 0)</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs {{ $this->balance['is_balanced'] ? 'text-brand-emerald' : 'text-error-deep' }}">
                {{ number_format($this->balance['ecart'], 0, ',', ' ') }} F
            </span>
        </div>
    </div>

    @unless($this->balance['is_balanced'])
        <div class="bg-error-red/10 border border-error-red/30 rounded-lg p-md mb-lg flex items-start gap-sm">
            <span class="material-symbols-outlined text-error-deep text-[20px]">warning</span>
            <div>
                <p class="text-xs font-bold text-error-deep">Balance Déséquilibrée</p>
                <p class="text-[11px] text-error-deep mt-xs">Une anomalie de saisie doit être corrigée avant toute clôture (périodique ou annuelle) de l'exercice.</p>
            </div>
        </div>
    @endunless

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase" rowspan="2">N° Compte</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase" rowspan="2">Libellé</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase" colspan="2">Solde Ouverture</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase" colspan="2">Mouvements Période</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase" colspan="2">Solde Final</th>
                    </tr>
                    <tr class="bg-surface-zebra border-b border-outline-variant">
                        <th class="px-md py-xs text-right text-[10px] text-outline font-bold uppercase">Débit</th>
                        <th class="px-md py-xs text-right text-[10px] text-outline font-bold uppercase">Crédit</th>
                        <th class="px-md py-xs text-right text-[10px] text-outline font-bold uppercase">Débit</th>
                        <th class="px-md py-xs text-right text-[10px] text-outline font-bold uppercase">Crédit</th>
                        <th class="px-md py-xs text-right text-[10px] text-outline font-bold uppercase">Débit</th>
                        <th class="px-md py-xs text-right text-[10px] text-outline font-bold uppercase">Crédit</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->balance['rows'] as $i => $row)
                        <tr class="rrow border-b border-outline-variant {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                            <td data-label="N° Compte" class="px-md py-sm text-xs font-mono font-bold">{{ $row['code'] }}</td>
                            <td data-label="Libellé" class="px-md py-sm text-xs">{{ $row['label'] }}</td>
                            <td data-label="Ouverture Débit" class="px-md py-sm text-xs text-right">{{ $row['opening_debit'] > 0 ? number_format($row['opening_debit'], 0, ',', ' ') : '—' }}</td>
                            <td data-label="Ouverture Crédit" class="px-md py-sm text-xs text-right">{{ $row['opening_credit'] > 0 ? number_format($row['opening_credit'], 0, ',', ' ') : '—' }}</td>
                            <td data-label="Mouvements Débit" class="px-md py-sm text-xs text-right">{{ $row['period_debit'] > 0 ? number_format($row['period_debit'], 0, ',', ' ') : '—' }}</td>
                            <td data-label="Mouvements Crédit" class="px-md py-sm text-xs text-right">{{ $row['period_credit'] > 0 ? number_format($row['period_credit'], 0, ',', ' ') : '—' }}</td>
                            <td data-label="Solde Final Débit" class="px-md py-sm text-xs text-right font-bold text-brand-emerald">{{ $row['final_debit'] > 0 ? number_format($row['final_debit'], 0, ',', ' ') : '—' }}</td>
                            <td data-label="Solde Final Crédit" class="px-md py-sm text-xs text-right font-bold text-error-deep">{{ $row['final_credit'] > 0 ? number_format($row['final_credit'], 0, ',', ' ') : '—' }}</td>
                        </tr>
                    @empty
                        <tr><td colspan="8" class="px-md py-lg text-center text-outline">Aucun compte mouvementé sur cette période.</td></tr>
                    @endforelse
                </tbody>
                @if(count($this->balance['rows']) > 0)
                    <tfoot>
                        <tr class="bg-brand-forest text-white font-bold">
                            <td class="px-md py-sm text-xs" colspan="2">TOTAUX</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($this->balance['total_opening_debit'], 0, ',', ' ') }}</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($this->balance['total_opening_credit'], 0, ',', ' ') }}</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($this->balance['total_period_debit'], 0, ',', ' ') }}</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($this->balance['total_period_credit'], 0, ',', ' ') }}</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($this->balance['total_final_debit'], 0, ',', ' ') }}</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($this->balance['total_final_credit'], 0, ',', ' ') }}</td>
                        </tr>
                    </tfoot>
                @endif
            </table>
        </div>
    </div>
</div>
