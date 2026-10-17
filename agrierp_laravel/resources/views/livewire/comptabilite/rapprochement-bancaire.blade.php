<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">sync_alt</span>Rapprochement Bancaire
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Pointage entre le Grand Livre ({{ $this->selectedAccount?->code ?? 'compte de trésorerie' }} — {{ $this->selectedAccount?->label ?? 'Banques' }}) et le relevé bancaire importé.</p>
        </div>
        <div class="flex items-center gap-xs">
            @can('manage-comptabilite')
                <label class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm cursor-pointer">
                    <span class="material-symbols-outlined text-[18px]">upload_file</span>Importer un Relevé (CSV)
                    <input type="file" wire:model="releve" accept=".csv,.txt" class="hidden">
                </label>
            @endcan
            <button type="button" wire:click="exportRapprochementPdf" wire:loading.attr="disabled" wire:target="exportRapprochementPdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
            </button>
        </div>
    </div>

    @if($releve)
        <div class="bg-info-blue/10 border border-info-blue/30 rounded-lg p-md mb-lg flex flex-wrap items-center gap-sm">
            <span class="material-symbols-outlined text-info-blue text-[18px]">description</span>
            <p class="text-xs text-on-surface flex-1">Fichier prêt : <strong>{{ $releve->getClientOriginalName() }}</strong> — format attendu <code>date;libellé;montant</code>, montant signé.</p>
            <button type="button" wire:click="importReleve" wire:loading.attr="disabled" wire:target="importReleve" class="bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">Lancer l'import</button>
            <button type="button" wire:click="$set('releve', null)" class="text-outline text-xs underline">Annuler</button>
        </div>
    @endif
    @error('releve') <p class="invalid-feedback mb-md">{{ $message }}</p> @enderror

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-lg flex flex-wrap items-center gap-sm">
        <label for="rappro-compte-select" class="text-[10px] text-brand-forest font-bold uppercase">Compte :</label>
        <select id="rappro-compte-select" wire:model.live="accountId" class="text-sm font-bold border border-outline-variant rounded-lg px-md py-2 bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
            @forelse($this->treasuryAccounts as $account)
                <option value="{{ $account->id }}">{{ $account->code }} — {{ $account->label }}</option>
            @empty
                <option value="">Aucun compte de trésorerie au plan comptable</option>
            @endforelse
        </select>
        <div class="flex items-center gap-xs bg-surface-zebra rounded-lg px-sm py-1">
            <input wire:model.live="startDate" type="date" class="text-xs font-bold text-brand-forest border-0 outline-none bg-transparent p-1">
            <span class="text-outline text-xs">au</span>
            <input wire:model.live="endDate" type="date" class="text-xs font-bold text-brand-forest border-0 outline-none bg-transparent p-1">
        </div>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-4 gap-md mb-lg">
        <div class="bg-white p-md rounded-lg border border-outline-variant border-l-4 border-l-brand-emerald shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">Solde Livre (Grand Livre)</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ number_format($this->reconciliation['solde_livre'], 0, ',', ' ') }} F</span>
        </div>
        <div class="bg-white p-md rounded-lg border border-outline-variant border-l-4 border-l-info-blue shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">Solde Relevé Bancaire</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ number_format($this->reconciliation['solde_releve'], 0, ',', ' ') }} F</span>
        </div>
        <div class="bg-white p-md rounded-lg border border-outline-variant border-l-4 border-l-accent-yellow shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">Opérations en Instance</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ number_format(abs($this->reconciliation['en_instance']), 0, ',', ' ') }} F</span>
        </div>
        <div class="p-md rounded-lg border shadow-sm {{ $this->reconciliation['is_balanced'] ? 'border-brand-emerald/30 bg-brand-emerald/5' : 'border-error-red/30 bg-error-red/10' }}">
            <span class="text-[10px] text-outline font-bold uppercase block">Écart (doit être 0)</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs {{ $this->reconciliation['is_balanced'] ? 'text-brand-emerald' : 'text-error-deep' }}">{{ number_format($this->reconciliation['ecart'], 0, ',', ' ') }} F</span>
        </div>
    </div>

    <div class="rounded-lg p-md mb-lg flex items-center gap-sm border {{ $this->reconciliation['is_balanced'] ? 'border-brand-emerald/30 bg-brand-emerald/5' : 'border-error-red/30 bg-error-red/10' }}">
        <span class="material-symbols-outlined {{ $this->reconciliation['is_balanced'] ? 'text-brand-emerald' : 'text-error-deep' }} text-[20px]">{{ $this->reconciliation['is_balanced'] ? 'check_circle' : 'warning' }}</span>
        <p class="text-xs font-bold {{ $this->reconciliation['is_balanced'] ? 'text-brand-emerald' : 'text-error-deep' }}">
            @if($this->reconciliation['is_balanced'])
                Rapprochement équilibré — Solde Livre corrigé des opérations en instance et des lignes non saisies = Solde Relevé.
            @else
                Rapprochement déséquilibré — écart de {{ number_format($this->reconciliation['ecart'], 0, ',', ' ') }} F à justifier avant toute clôture.
            @endif
        </p>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-md">
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <div class="px-md py-sm border-b-2 border-brand-emerald bg-brand-emerald/5"><h3 class="text-sm font-bold text-brand-emerald uppercase">Grand Livre ({{ $this->selectedAccount?->code ?? '—' }})</h3></div>
            <div class="overflow-x-auto">
                <table class="w-full rtable">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Libellé</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Montant</th>
                            <th class="px-md py-sm text-center text-[10px] text-outline font-bold uppercase">Statut</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($this->reconciliation['ledger'] as $i => $ligne)
                            <tr class="rrow border-b border-outline-variant {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                                <td data-label="Date" class="px-md py-sm text-xs">{{ \Carbon\Carbon::parse($ligne['date'])->format('d/m/Y') }}</td>
                                <td data-label="Libellé" class="px-md py-sm text-xs">{{ $ligne['label'] }}</td>
                                <td data-label="Montant" class="px-md py-sm text-xs text-right font-bold {{ $ligne['amount'] >= 0 ? 'text-brand-emerald' : 'text-error-deep' }}">{{ number_format($ligne['amount'], 0, ',', ' ') }}</td>
                                <td data-label="Statut" class="px-md py-sm text-center">
                                    @if($ligne['is_matched'])
                                        <span class="text-[11px] font-bold px-sm py-0.5 rounded-full bg-brand-emerald/10 text-brand-emerald">Pointé</span>
                                    @else
                                        <span class="text-[11px] font-bold px-sm py-0.5 rounded-full bg-accent-yellow/20 text-brand-forest">En Instance</span>
                                    @endif
                                </td>
                            </tr>
                        @empty
                            <tr><td colspan="4" class="px-md py-lg text-center text-outline">Aucune écriture sur ce compte pour la période.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
        </div>

        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <div class="px-md py-sm border-b-2 border-info-blue bg-info-blue/5"><h3 class="text-sm font-bold text-info-blue uppercase">Relevé Bancaire Importé</h3></div>
            <div class="overflow-x-auto">
                <table class="w-full rtable">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Libellé</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Montant</th>
                            <th class="px-md py-sm text-center text-[10px] text-outline font-bold uppercase">Statut</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($this->reconciliation['statement'] as $i => $ligne)
                            <tr class="rrow border-b border-outline-variant {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                                <td data-label="Date" class="px-md py-sm text-xs">{{ \Carbon\Carbon::parse($ligne['date'])->format('d/m/Y') }}</td>
                                <td data-label="Libellé" class="px-md py-sm text-xs">{{ $ligne['label'] }}</td>
                                <td data-label="Montant" class="px-md py-sm text-xs text-right font-bold {{ $ligne['amount'] >= 0 ? 'text-brand-emerald' : 'text-error-deep' }}">{{ number_format($ligne['amount'], 0, ',', ' ') }}</td>
                                <td data-label="Statut" class="px-md py-sm text-center">
                                    @if($ligne['is_matched'])
                                        <span class="text-[11px] font-bold px-sm py-0.5 rounded-full bg-brand-emerald/10 text-brand-emerald">Pointé</span>
                                    @else
                                        <span class="text-[11px] font-bold px-sm py-0.5 rounded-full bg-info-blue/10 text-info-blue">Nouveau — À Saisir</span>
                                    @endif
                                </td>
                            </tr>
                        @empty
                            <tr><td colspan="4" class="px-md py-lg text-center text-outline">Aucun relevé importé pour ce compte sur la période.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
        </div>
    </div>

    <div class="bg-surface-zebra border border-outline-variant rounded-lg p-md mt-lg text-xs text-outline">
        <p><strong class="text-brand-forest">Lettrage automatique :</strong> une écriture et une ligne de relevé sont appariées lorsqu'elles portent le même montant à moins de {{ \App\Services\BankReconciliationService::TOLERANCE_JOURS }} jours d'écart — le délai normal de traitement bancaire. Chaque ligne n'est appariée qu'une seule fois, afin qu'un doublon réel ne puisse jamais être masqué par un double lettrage.</p>
    </div>
</div>
