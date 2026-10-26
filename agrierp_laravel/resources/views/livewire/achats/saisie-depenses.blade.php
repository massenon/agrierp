<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">request_page</span>Saisie des Dépenses
        </h2>
        <p class="text-xs text-outline mt-xs">Enregistrement des charges d'exploitation courantes de la ferme (SYSCOHADA Classe 6).</p>
    </div>

    <div class="grid grid-cols-1 sm:grid-cols-3 gap-md mb-lg">
        <x-kpi-card label="Dépenses du mois" icon="payments" color="emerald" :value="number_format($this->kpis['depenses_mois'], 0, ',', ' ').' FCFA'" />
        <x-kpi-card label="Charges Fixes" icon="event_repeat" color="maize" :pending="true" pending-since="Aucun champ Fixe/Variable dans le formulaire source" />
        <x-kpi-card label="Charges Variables" icon="trending_down" color="blue" :pending="true" pending-since="Aucun champ Fixe/Variable dans le formulaire source" />
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-md flex flex-wrap items-center gap-sm">
        <div class="relative flex-1 min-w-[180px]">
            <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
            <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
        </div>
        <select wire:model.live="pieceFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">Toutes les pièces</option>
            <option>Comptabilisée</option>
            <option>Sans pièce</option>
        </select>
        <button @lectureSeule type="button" wire:click="nouvelleDepense" class="py-sm px-lg rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm flex items-center justify-center gap-xs">
            <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouvelle Dépense
        </button>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Libellé</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Total</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Mode</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Pièce</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                @forelse($this->expenses as $i => $expense)
                    @php $comptabilisee = $expense->accounting_entry_id !== null; @endphp
                    <tbody x-data="{ ouvert: false }" wire:key="depense-{{ $expense->id }}">
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Date" class="px-md py-sm text-xs">{{ $expense->expense_date->format('d/m/Y') }}</td>
                            <td data-label="Libellé" class="px-md py-sm text-xs font-semibold">
                                <button type="button" x-on:click="ouvert = !ouvert" x-bind:aria-expanded="ouvert" class="flex items-center gap-xs text-left hover:text-brand-emerald" title="Voir les lignes">
                                    <span class="material-symbols-outlined text-[18px]" x-text="ouvert ? 'expand_less' : 'expand_more'">expand_more</span>{{ $expense->label }}
                                </button>
                            </td>
                            <td data-label="Total" class="px-md py-sm text-xs text-right font-bold">{{ number_format($expense->amount, 0, ',', ' ') }} FCFA</td>
                            <td data-label="Mode" class="px-md py-sm text-xs">{{ $expense->on_credit ? 'À crédit' : (\App\Models\Expense::MODES_DE_PAIEMENT[$expense->payment_mode] ?? '—') }}</td>
                            <td data-label="Pièce" class="px-md py-sm">
                                @if($comptabilisee)
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">{{ $expense->accountingEntry?->numero ?: 'Comptabilisée' }}</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">Sans pièce</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                @unless($comptabilisee)
                                    <button @lectureSeule type="button" wire:click="editExpense('{{ $expense->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                @endunless
                                <button @lectureSeule type="button" x-on:click="$dispatch('open-modal', { name: 'archive-expense-{{ $expense->id }}' })" class="text-outline hover:text-error-deep p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">delete</span></button>
                            </td>
                        </tr>
                        <tr x-show="ouvert" x-cloak class="border-b border-outline-variant bg-surface-zebra">
                            <td colspan="6" class="px-md py-sm">
                                <table class="w-full">
                                    <thead>
                                        <tr>
                                            <th class="py-xs text-left text-[10px] text-outline font-bold uppercase">Libellé</th>
                                            <th class="py-xs text-left text-[10px] text-outline font-bold uppercase">Compte de Charge</th>
                                            <th class="py-xs text-right text-[10px] text-outline font-bold uppercase">Montant</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        @forelse($expense->lines as $ligne)
                                            <tr class="border-t border-outline-variant">
                                                <td class="py-xs text-xs">{{ $ligne->label }}</td>
                                                <td class="py-xs text-xs">{{ $ligne->chargeAccount?->code }} - {{ $ligne->chargeAccount?->label }}</td>
                                                <td class="py-xs text-xs text-right font-semibold">{{ number_format($ligne->amount, 0, ',', ' ') }} FCFA</td>
                                            </tr>
                                        @empty
                                            <tr class="border-t border-outline-variant"><td colspan="3" class="py-xs text-xs text-outline">Aucune ligne.</td></tr>
                                        @endforelse
                                    </tbody>
                                </table>
                                <p class="text-[11px] text-outline mt-xs">
                                    Trésorerie : {{ $expense->treasuryAccount?->label ?? '—' }}
                                    · Centre de coût : {{ $expense->costCenter?->label ?? '—' }}
                                    · Fournisseur : {{ $expense->supplier?->name ?? '—' }}
                                    · Bénéficiaire : {{ $expense->beneficiary ?: '—' }}
                                    · Règlement : {{ \App\Models\Expense::libelleReglement((bool) $expense->on_credit, $expense->status) }}
                                    · Saisie par : {{ $expense->creator?->name ?? '—' }}
                                </p>
                            </td>
                        </tr>
                    </tbody>
                    <x-modal-confirm-delete :name="'archive-expense-'.$expense->id" :item-label="$expense->label" :action="'archiveExpense(\''.$expense->id.'\')'" />
                @empty
                    <tbody><tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucune dépense pour le moment.</td></tr></tbody>
                @endforelse
            </table>
        </div>
        <x-pagination :paginator="$this->expenses" />
    </div>
    <x-modal name="modal-depense" max-width="xl">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest flex items-center gap-xs">
                <span class="material-symbols-outlined text-[20px]">add_circle</span>{{ $editingExpenseId ? 'Modifier la Dépense' : 'Nouvelle Dépense' }}
            </h3>
            <button type="button" x-on:click="show = false" class="text-outline hover:text-on-surface" title="Fermer"><span class="material-symbols-outlined text-[20px]">close</span></button>
        </div>
        <p class="text-xs text-outline mb-md">Enregistrez une charge d'exploitation de trésorerie directe : une dépense, plusieurs lignes.</p>
        @error('formulaire') <p class="invalid-feedback mb-sm">{{ $message }}</p> @enderror
        <form wire:submit="submitExpense" class="grid grid-cols-1 md:grid-cols-2 gap-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date de la Transaction *</label>
                <input wire:model="expenseDate" type="date" @if($this->dateMinSaisie) min="{{ $this->dateMinSaisie }}" @endif class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('expenseDate') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('expenseDate') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            @unless($this->aCredit)
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Mode de Paiement *</label>
                <select wire:model.live="paymentMode" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('paymentMode') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach(\App\Models\Expense::MODES_DE_PAIEMENT as $cle => $libelle)
                        <option value="{{ $cle }}">{{ $libelle }}</option>
                    @endforeach
                </select>
                @error('paymentMode') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Compte de Trésorerie Débité *</label>
                <select wire:model.live="treasuryAccountId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('treasuryAccountId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->treasuryAccounts as $account)
                        <option value="{{ $account->id }}">{{ $account->label }} ({{ number_format($account->balance, 0, ',', ' ') }} FCFA)</option>
                    @endforeach
                </select>
                @error('treasuryAccountId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            @endunless
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Centre de Coût *</label>
                <select wire:model="costCenterId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('costCenterId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->costCenters as $centre)
                        <option value="{{ $centre->id }}">{{ $centre->label }}</option>
                    @endforeach
                </select>
                @error('costCenterId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Fournisseur</label>
                <select wire:model.live="supplierId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('supplierId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Aucun --</option>
                    @foreach($this->suppliers as $fournisseur)
                        <option value="{{ $fournisseur->id }}">{{ $fournisseur->name }}</option>
                    @endforeach
                </select>
                @error('supplierId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            @if($supplierId !== '')
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Règlement *</label>
                    <select wire:model.live="reglement" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('reglement') ? 'is-invalid' : 'border-outline-variant' }}">
                        @foreach(\App\Models\Expense::REGLEMENTS as $cle => $libelle)
                            <option value="{{ $cle }}">{{ $libelle }}</option>
                        @endforeach
                    </select>
                    @error('reglement') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    @if($this->aCredit)
                        <p class="text-[10px] text-outline mt-xs" data-aide-credit>Aucune trésorerie n'est touchée : la dette est créée au nom du fournisseur et se règle dans « Dettes Fournisseurs ».</p>
                    @endif
                </div>
            @endif
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Bénéficiaire</label>
                <input wire:model="beneficiary" type="text" placeholder="ex : M. Dossou (si ce n'est pas un fournisseur)" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('beneficiary') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('beneficiary') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="md:col-span-2">
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Reçu / Facture (Photo)</label>
                <label class="border-2 border-dashed border-outline-variant rounded-lg p-md text-center h-11 flex items-center justify-center gap-xs cursor-pointer hover:border-brand-emerald">
                    <input wire:model="receiptFile" type="file" accept="image/*" class="hidden">
                    <span class="material-symbols-outlined text-outline-variant text-[18px]">add_a_photo</span>
                    <p class="text-[10px] text-outline">{{ $receiptFile ? $receiptFile->getClientOriginalName() : 'Associer le justificatif (JPG/PNG, max 5Mo)' }}</p>
                </label>
                @error('receiptFile') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            <div class="md:col-span-2">
                <div class="flex items-center justify-between mb-xs">
                    <h4 class="text-[10px] text-brand-forest font-bold uppercase">Lignes de la Dépense *</h4>
                    <button type="button" wire:click="addLine" class="text-xs font-bold text-brand-emerald hover:text-brand-forest flex items-center gap-xs">
                        <span class="material-symbols-outlined text-[18px]">add</span>Ajouter une ligne
                    </button>
                </div>
                @error('lines') <p class="invalid-feedback mb-xs">{{ $message }}</p> @enderror
                <div class="grid grid-cols-12 gap-sm mb-xs">
                    <span class="col-span-5 text-[10px] text-outline font-bold uppercase">Libellé *</span>
                    <span class="col-span-4 text-[10px] text-outline font-bold uppercase">Compte de Charge *</span>
                    <span class="col-span-2 text-[10px] text-outline font-bold uppercase">Montant (FCFA) *</span>
                    <span class="col-span-1"></span>
                </div>
                @foreach($lines as $i => $ligne)
                    <div class="grid grid-cols-12 gap-sm mb-sm items-start" wire:key="ligne-depense-{{ $i }}">
                        <div class="col-span-5">
                            <input wire:model="lines.{{ $i }}.label" type="text" placeholder="ex : Carburant livraison ou Achat provende Lot 3" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('lines.'.$i.'.label') ? 'is-invalid' : 'border-outline-variant' }}">
                            @error('lines.'.$i.'.label') <p class="invalid-feedback">{{ $message }}</p> @enderror
                        </div>
                        <div class="col-span-4">
                            <select wire:model="lines.{{ $i }}.chargeAccountId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('lines.'.$i.'.chargeAccountId') ? 'is-invalid' : 'border-outline-variant' }}">
                                <option value="">-- Sélectionner --</option>
                                @foreach($this->chargeAccounts as $compte)
                                    <option value="{{ $compte->id }}">{{ $compte->code }} - {{ $compte->label }}</option>
                                @endforeach
                            </select>
                            @error('lines.'.$i.'.chargeAccountId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                        </div>
                        <div class="col-span-2">
                            <input wire:model.live.debounce.300ms="lines.{{ $i }}.amount" type="number" min="1" step="1" placeholder="ex : 25000" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('lines.'.$i.'.amount') ? 'is-invalid' : 'border-outline-variant' }}">
                            @error('lines.'.$i.'.amount') <p class="invalid-feedback">{{ $message }}</p> @enderror
                        </div>
                        <div class="col-span-1 flex justify-end">
                            <button type="button" wire:click="removeLine({{ $i }})" @disabled(count($lines) < 2) class="h-11 px-xs text-outline hover:text-error-deep disabled:opacity-30" title="Retirer la ligne"><span class="material-symbols-outlined text-[18px]">delete</span></button>
                        </div>
                    </div>
                @endforeach
                @error('total') <p class="invalid-feedback">{{ $message }}</p> @enderror
                <div class="flex justify-end border-t border-outline-variant pt-sm">
                    <p class="text-sm font-bold text-brand-forest">Total : <span data-total-depense>{{ number_format($this->total, 0, ',', ' ') }}</span> FCFA</p>
                </div>
            </div>

            <div class="md:col-span-2 flex justify-end">
                <button @lectureSeule type="submit" wire:loading.attr="disabled" wire:target="submitExpense" class="py-sm px-lg rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm flex items-center justify-center gap-xs disabled:opacity-50">
                    <span class="material-symbols-outlined text-[18px]">save</span>Enregistrer la Dépense
                </button>
            </div>
        </form>
    </x-modal>
</div>
