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

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-lg mb-lg">
        <h3 class="font-bold text-lg text-brand-forest mb-md flex items-center gap-xs">
            <span class="material-symbols-outlined text-[20px]">add_circle</span>{{ $editingExpenseId ? 'Modifier la Dépense' : 'Nouvelle Dépense' }}
        </h3>
        <p class="text-xs text-outline mb-md">Enregistrez une charge d'exploitation de trésorerie directe.</p>
        <form wire:submit="submitExpense" class="grid grid-cols-1 md:grid-cols-2 gap-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date de la Transaction *</label>
                <input wire:model="expenseDate" type="date" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('expenseDate') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('expenseDate') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Libellé de la Dépense *</label>
                <input wire:model="label" type="text" placeholder="ex : Carburant livraison ou Achat provende Lot 3" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('label') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('label') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Catégorie de Charges (SYSCOHADA) *</label>
                <select wire:model="category" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('category') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach(\App\Models\Expense::CATEGORIES as $compte)
                        <option>{{ $compte }}</option>
                    @endforeach
                </select>
                @error('category') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Montant Décaissé (FCFA) *</label>
                <input wire:model="amount" type="number" placeholder="ex : 25000" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('amount') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('amount') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Compte de Trésorerie Débité *</label>
                <select wire:model="treasuryAccountId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('treasuryAccountId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->treasuryAccounts as $account)
                        <option value="{{ $account->id }}">{{ $account->label }} ({{ number_format($account->balance, 0, ',', ' ') }} FCFA)</option>
                    @endforeach
                </select>
                @error('treasuryAccountId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Reçu / Facture (Photo)</label>
                <label class="border-2 border-dashed border-outline-variant rounded-lg p-md text-center h-11 flex items-center justify-center gap-xs cursor-pointer hover:border-brand-emerald">
                    <input wire:model="receiptFile" type="file" accept="image/*" class="hidden">
                    <span class="material-symbols-outlined text-outline-variant text-[18px]">add_a_photo</span>
                    <p class="text-[10px] text-outline">{{ $receiptFile ? $receiptFile->getClientOriginalName() : 'Associer le justificatif (JPG/PNG, max 5Mo)' }}</p>
                </label>
                @error('receiptFile') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="md:col-span-2 flex justify-end">
                <button type="submit" wire:loading.attr="disabled" wire:target="submitExpense" class="py-sm px-lg rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm flex items-center justify-center gap-xs disabled:opacity-50">
                    <span class="material-symbols-outlined text-[18px]">save</span>Enregistrer la Dépense
                </button>
            </div>
        </form>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-md flex flex-wrap items-center gap-sm">
        <div class="relative flex-1 min-w-[180px]">
            <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
            <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
        </div>
        <select wire:model.live="statusFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">Tous les statuts</option>
            <option>Payée</option>
            <option>En attente</option>
        </select>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Libellé</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Catégorie</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Montant</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->expenses as $i => $expense)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Date" class="px-md py-sm text-xs">{{ $expense->expense_date->format('d/m/Y') }}</td>
                            <td data-label="Libellé" class="px-md py-sm text-xs font-semibold">{{ $expense->label }}</td>
                            <td data-label="Catégorie" class="px-md py-sm text-xs">{{ $expense->category }}</td>
                            <td data-label="Montant" class="px-md py-sm text-xs text-right font-bold">{{ number_format($expense->amount, 0, ',', ' ') }} FCFA</td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($expense->status === 'payee')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Payée</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">En attente</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button" wire:click="editExpense('{{ $expense->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-expense-{{ $expense->id }}' })" class="text-outline hover:text-error-deep p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">delete</span></button>
                            </td>
                        </tr>
                        <x-modal-confirm-delete :name="'archive-expense-'.$expense->id" :item-label="$expense->label" :action="'archiveExpense(\''.$expense->id.'\')'" />
                    @empty
                        <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucune dépense pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
</div>
