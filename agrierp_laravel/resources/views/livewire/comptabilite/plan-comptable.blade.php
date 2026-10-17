<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">menu_book</span>Plan Comptable SYSCOHADA
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Nomenclature des comptes du référentiel SYSCOHADA révisé.</p>
        </div>
        <div class="flex items-center gap-xs">
            <button type="button" wire:click="exportPlanComptablePdf" wire:loading.attr="disabled" wire:target="exportPlanComptablePdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
            </button>
            @can('manage-comptabilite')
            <button type="button" wire:click="newAccount" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
                <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouveau Compte
            </button>
            @endcan
        </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md mb-lg">
        <x-kpi-card label="Comptes actifs" icon="menu_book" color="emerald" :value="$this->kpis['comptes_actifs']" />
        <x-kpi-card label="Exercice" icon="event" color="blue" :value="$this->kpis['exercice']" />
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
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">N° Compte</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Intitulé</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Classe</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->accounts as $i => $account)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="N° Compte" class="px-md py-sm text-xs font-mono font-bold text-brand-emerald">{{ $account->code }}</td>
                            <td data-label="Intitulé" class="px-md py-sm text-xs font-semibold">{{ $account->label }}</td>
                            <td data-label="Classe" class="px-md py-sm text-xs">{{ $this->classLabel($account->class) }}</td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                @can('manage-comptabilite')
                                <button type="button" wire:click="editAccount('{{ $account->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                <button type="button" wire:click="archiveAccount('{{ $account->id }}')" class="text-error-deep hover:text-red-800 p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">archive</span></button>
                                @else
                                <span class="text-outline text-[10px] italic">Lecture seule</span>
                                @endcan
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="4" class="px-md py-lg text-center text-outline">Aucun compte pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        @if($this->totalCorrespondant > $this->accounts->count())
            <div class="p-md border-t border-outline-variant flex items-center justify-between gap-sm">
                <p class="text-xs text-outline">{{ $this->accounts->count() }} comptes affichés sur {{ $this->totalCorrespondant }} — la recherche porte sur tout le plan.</p>
                <button type="button" wire:click="afficherPlus" class="px-md py-sm rounded-lg border border-outline-variant text-xs font-bold text-brand-forest hover:bg-surface-zebra">Afficher plus</button>
            </div>
        @endif
    </div>

    <x-modal name="modal-create-plan-comptable" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingId ? 'Modifier le Compte' : 'Nouveau Compte' }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-plan-comptable' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveAccount" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Numéro de compte *</label>
                <input wire:model="code" type="text" placeholder="ex : 411" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('code') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('code') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Intitulé *</label>
                <input wire:model="label" type="text" placeholder="ex : Clients" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('label') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('label') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Classe *</label>
                <select wire:model="class" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('class') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    <option value="1">1 - Ressources</option>
                    <option value="2">2 - Immobilisations</option>
                    <option value="3">3 - Stocks</option>
                    <option value="4">4 - Tiers</option>
                    <option value="5">5 - Trésorerie</option>
                    <option value="6">6 - Charges</option>
                    <option value="7">7 - Produits</option>
                    <option value="8">8 - Autres</option>
                    <option value="9">9 - Hors bilan et analytique</option>
                </select>
                @error('class') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="flex justify-end gap-sm pt-md border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-plan-comptable' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>
</div>
