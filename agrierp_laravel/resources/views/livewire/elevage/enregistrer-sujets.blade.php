<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">pets</span>Enregistrer des Sujets
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Journal des ENTRÉES (Phase 1 du cycle) : naissances locales et acquisitions externes. Chaque entrée valide alimente ensuite une Bande/Lot pour le suivi continu de l'effectif.</p>
        </div>
        <button type="button" wire:click="newEntry" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
            <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouveau Sujet
        </button>
    </div>

    <x-kpi-accordion title="Indicateurs de performance">
        <x-kpi-card label="Naissances (mois)" icon="child_care" color="emerald" :value="$this->kpis['naissances_mois']" />
        <x-kpi-card label="Acquisitions (mois)" icon="shopping_cart" color="emerald" :value="$this->kpis['acquisitions_mois']" />
        <x-kpi-card label="Effectif Total" icon="pets" color="emerald" :value="number_format($this->kpis['effectif_total'], 0, ',', ' ')" />
    </x-kpi-accordion>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md flex flex-col md:flex-row items-stretch md:items-center justify-between gap-sm border-b border-outline-variant">
            <div class="relative flex-1 md:max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher un code de bande..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
            </div>
            <select wire:model.live="statut" class="border border-outline-variant rounded-lg text-xs px-sm py-2 bg-white w-full md:w-auto">
                <option value="">Tous les statuts</option>
                <option value="Naissance">Naissance</option>
                <option value="Achat">Achat</option>
            </select>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase tracking-wider">Date</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase tracking-wider">Bande</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase tracking-wider">Espèce</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase tracking-wider">Origine</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase tracking-wider">Quantité</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->entries as $i => $entry)
                        @php
                            $origine = $entry->ne > 0 ? 'Naissance' : ($entry->achat > 0 ? 'Achat' : 'Don');
                            $qty = $entry->ne > 0 ? $entry->ne : ($entry->achat > 0 ? $entry->achat : $entry->don);
                        @endphp
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 transition-colors {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Date" class="px-md py-sm text-xs whitespace-nowrap">{{ $entry->entry_date->format('d/m/Y') }}</td>
                            <td data-label="Bande" class="px-md py-sm text-xs font-bold text-brand-emerald whitespace-nowrap">{{ $entry->lot?->code }}</td>
                            <td data-label="Espèce" class="px-md py-sm text-xs whitespace-nowrap">{{ $entry->lot?->species?->label }}</td>
                            <td data-label="Origine" class="px-md py-sm text-xs whitespace-nowrap">
                                <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border {{ $origine === 'Naissance' ? 'bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30' : 'bg-blue-100 text-info-blue border-blue-300' }}">{{ $origine }}</span>
                            </td>
                            <td data-label="Quantité" class="px-md py-sm text-xs whitespace-nowrap">{{ $qty }}</td>
                        </tr>
                    @empty
                        <tr>
                            <td colspan="5" class="px-md py-xl text-center">
                                <span class="material-symbols-outlined text-outline-variant text-[44px] block mb-sm">inbox</span>
                                <p class="text-sm font-semibold text-on-surface">Aucun résultat trouvé</p>
                                <button type="button" wire:click="newEntry" class="text-xs font-bold text-brand-emerald mt-sm">+ Nouveau Sujet</button>
                            </td>
                        </tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-create-sujet" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Nouveau Sujet</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-sujet' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveEntry" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">Espèce *</label>
                <select wire:model.live="species_id" class="w-full h-11 px-md border rounded-lg bg-white text-sm {{ $errors->has('species_id') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->speciesOptions as $sp)
                        <option value="{{ $sp->id }}">{{ $sp->label }}</option>
                    @endforeach
                </select>
                @error('species_id') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">Bande / Lot de destination *</label>
                <select wire:model="lot_id" class="w-full h-11 px-md border rounded-lg bg-white text-sm {{ $errors->has('lot_id') ? 'is-invalid' : 'border-outline-variant' }}" @if(!$species_id) disabled @endif>
                    <option value="">{{ $species_id ? '-- Sélectionner --' : "Choisir d'abord une espèce" }}</option>
                    @foreach($this->lotOptions as $lot)
                        <option value="{{ $lot->id }}">{{ $lot->code }} ({{ $lot->current_quantity }} têtes)</option>
                    @endforeach
                </select>
                <p class="text-[10px] text-outline mt-xs">Champ nécessaire pour rattacher l'entrée à une bande réelle — non présent tel quel dans le formulaire d'origine (voir docblock du composant).</p>
                @error('lot_id') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">Origine *</label>
                <select wire:model="origine" class="w-full h-11 px-md border rounded-lg bg-white text-sm {{ $errors->has('origine') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    <option value="Naissance">Naissance</option>
                    <option value="Achat">Achat</option>
                    <option value="Don">Don</option>
                </select>
                @error('origine') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">Quantité *</label>
                <input wire:model="quantite" type="number" min="1" class="w-full h-11 px-md border rounded-lg bg-white text-sm {{ $errors->has('quantite') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('quantite') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase tracking-wider mb-xs">Date *</label>
                <input wire:model="entry_date" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg bg-white text-sm">
            </div>
            <div class="flex justify-end gap-sm pt-md border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-sujet' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>
</div>
