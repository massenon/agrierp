<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">import_contacts</span>Grand Livre
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Écritures chronologiques d'un compte, avec solde progressif.</p>
        </div>
        <div class="flex items-center gap-xs">
            <button type="button" wire:click="exportGrandLivrePdf" wire:loading.attr="disabled" wire:target="exportGrandLivrePdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
            </button>
        </div>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-lg flex flex-wrap items-center gap-sm">
        <label for="gl-compte-select" class="text-[10px] text-brand-forest font-bold uppercase">Compte :</label>
        <select id="gl-compte-select" wire:model.live="accountId" class="text-sm font-bold border border-outline-variant rounded-lg px-md py-2 bg-white min-w-[260px] focus:ring-2 focus:ring-brand-emerald outline-none">
            @forelse($this->accounts as $account)
                <option value="{{ $account->id }}">{{ $account->code }} — {{ $account->label }}</option>
            @empty
                <option value="">Aucun compte au plan comptable</option>
            @endforelse
        </select>
        <div class="flex items-center gap-xs bg-surface-zebra rounded-lg px-sm py-1">
            <input wire:model.live="startDate" type="date" class="text-xs font-bold text-brand-forest border-0 outline-none bg-transparent p-1">
            <span class="text-outline text-xs">au</span>
            <input wire:model.live="endDate" type="date" class="text-xs font-bold text-brand-forest border-0 outline-none bg-transparent p-1">
        </div>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-md mb-lg">
        <x-kpi-card label="Solde d'Ouverture" color="emerald" :value="number_format($this->ledger['opening_balance'], 0, ',', ' ').' F'" />
        <x-kpi-card label="Total Débit Période" color="blue" :value="number_format($this->ledger['total_debit'], 0, ',', ' ').' F'" />
        <x-kpi-card label="Total Crédit Période" color="red" :value="number_format($this->ledger['total_credit'], 0, ',', ' ').' F'" />
        <x-kpi-card label="Solde Final" color="maize" :value="number_format($this->ledger['closing_balance'], 0, ',', ' ').' F'" />
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-md">
        <div class="relative max-w-xs">
            <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
            <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher un libellé, une pièce..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
        </div>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase tracking-wider">Date</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase tracking-wider">N° Pièce</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase tracking-wider">Libellé</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase tracking-wider">Débit</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase tracking-wider">Crédit</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase tracking-wider">Solde Progressif</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach($this->ledger['lines'] as $i => $line)
                        <tr class="rrow border-b border-outline-variant {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                            <td data-label="Date" class="px-md py-sm text-xs">{{ \Carbon\Carbon::parse($line['date'])->format('d/m/Y') }}</td>
                            <td data-label="N° Pièce" class="px-md py-sm text-xs font-mono text-outline">{{ $line['reference'] }}</td>
                            <td data-label="Libellé" class="px-md py-sm text-xs">{{ $line['label'] }}</td>
                            <td data-label="Débit" class="px-md py-sm text-xs text-right {{ $line['debit'] > 0 ? 'font-bold text-brand-emerald' : 'text-outline' }}">{{ $line['debit'] > 0 ? number_format($line['debit'], 0, ',', ' ') : '—' }}</td>
                            <td data-label="Crédit" class="px-md py-sm text-xs text-right {{ $line['credit'] > 0 ? 'font-bold text-error-deep' : 'text-outline' }}">{{ $line['credit'] > 0 ? number_format($line['credit'], 0, ',', ' ') : '—' }}</td>
                            <td data-label="Solde Progressif" class="px-md py-sm text-xs text-right font-bold text-brand-forest">{{ number_format($line['running_balance'], 0, ',', ' ') }}</td>
                        </tr>
                    @endforeach
                </tbody>
            </table>
        </div>
        @if(count($this->ledger['lines']) === 0)
            <div class="text-center py-xl">
                <span class="material-symbols-outlined text-outline-variant text-[40px] block mb-xs">search_off</span>
                <p class="text-xs text-outline">Aucune écriture ne correspond à ces critères.</p>
            </div>
        @endif
    </div>
</div>
