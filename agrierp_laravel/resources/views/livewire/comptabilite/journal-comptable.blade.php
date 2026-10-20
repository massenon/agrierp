<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">account_balance</span>Journal Comptable
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Écritures comptables, double entrée SYSCOHADA.</p>
        </div>
        <div class="flex items-center gap-xs">
            <button type="button" wire:click="exportJournalPdf" wire:loading.attr="disabled" wire:target="exportJournalPdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
            </button>
            @can('manage-comptabilite')
            <button @lectureSeule type="button" wire:click="newEntry" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
                <span class="material-symbols-outlined text-[18px]">add_circle</span>Saisie d'Écriture
            </button>
            @endcan
        </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md mb-lg">
        <x-kpi-card label="Écritures (mois)" icon="receipt_long" color="emerald" :value="$this->kpis['ecritures_mois']" />
        <x-kpi-card label="Total Débit" icon="arrow_downward" color="blue" :value="number_format($this->kpis['total_debit'], 0, ',', ' ').' F'" />
        <x-kpi-card label="Total Crédit" icon="arrow_upward" color="maize" :value="number_format($this->kpis['total_credit'], 0, ',', ' ').' F'" />
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md border-b border-outline-variant">
            <div class="relative max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
            </div>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">N° Pièce</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Libellé</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Débit</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Crédit</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Montant</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->entries as $i => $entry)
                        @php
                            $refParts = explode('—', (string) $entry->reference, 2);
                            $piece = trim($refParts[0] ?? '');
                            $label = trim($refParts[1] ?? '');
                            $debitLine = $this->debitLine($entry);
                            $creditLine = $this->creditLine($entry);
                        @endphp
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="N° Pièce" class="px-md py-sm text-xs font-mono font-bold text-brand-emerald">{{ $piece }}</td>
                            <td data-label="Date" class="px-md py-sm text-xs">{{ $entry->entry_date->format('d/m/Y') }}</td>
                            <td data-label="Libellé" class="px-md py-sm text-xs font-semibold">{{ $label }}</td>
                            <td data-label="Débit" class="px-md py-sm text-xs">{{ $debitLine?->account?->code }} - {{ $debitLine?->account?->label }}</td>
                            <td data-label="Crédit" class="px-md py-sm text-xs">{{ $creditLine?->account?->code }} - {{ $creditLine?->account?->label }}</td>
                            <td data-label="Montant" class="px-md py-sm text-xs text-right font-bold">{{ number_format($entry->total_debit, 0, ',', ' ') }}</td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                @if($entry->is_locked)
                                    <span class="material-symbols-outlined text-[16px] text-outline align-middle" title="Écriture verrouillée (exercice clôturé)">lock</span>
                                @elseif(auth()->user()->can('manage-comptabilite'))
                                    <button @lectureSeule type="button" wire:click="editEntry('{{ $entry->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                    <button @lectureSeule type="button" wire:click="archiveEntry('{{ $entry->id }}')" class="text-error-deep hover:text-red-800 p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">archive</span></button>
                                @else
                                    <span class="text-outline text-[10px] italic">Lecture seule</span>
                                @endif
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="7" class="px-md py-lg text-center text-outline">Aucune écriture pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <x-pagination :paginator="$this->entries" />
    </div>

    <x-modal name="modal-create-journal-comptable" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingId ? "Modifier l'Écriture" : "Saisie d'Écriture" }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-journal-comptable' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveEntry" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date de l'écriture *</label>
                <input wire:model="entryDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Libellé *</label>
                <input wire:model="label" type="text" placeholder="ex : Achat aliment ponte" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('label') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('label') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Compte à débiter *</label>
                <select wire:model="debitAccountId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('debitAccountId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->accounts as $account)
                        <option value="{{ $account->id }}">{{ $account->code }} - {{ $account->label }}</option>
                    @endforeach
                </select>
                @error('debitAccountId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Compte à créditer *</label>
                <select wire:model="creditAccountId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('creditAccountId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->accounts as $account)
                        <option value="{{ $account->id }}">{{ $account->code }} - {{ $account->label }}</option>
                    @endforeach
                </select>
                @error('creditAccountId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Montant (FCFA) *</label>
                <input wire:model="amount" type="number" min="1" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('amount') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('amount') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="flex justify-end gap-sm pt-md border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-journal-comptable' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button @lectureSeule type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>
</div>
