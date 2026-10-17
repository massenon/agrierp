<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">pets</span>Registre des Reproducteurs
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Sujets suivis individuellement — identification, race, généalogie. Les bandes d'engraissement restent suivies en quantités.</p>
        </div>
        @can('manage-elevage')
            <button type="button" wire:click="newAnimal" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
                <span class="material-symbols-outlined text-[18px]">add_circle</span>Enregistrer un Reproducteur
            </button>
        @endcan
    </div>

    <div class="bg-info-blue/10 border border-info-blue/30 rounded-lg p-md mb-lg flex items-start gap-sm text-xs">
        <span class="material-symbols-outlined text-info-blue text-[18px] flex-shrink-0">info</span>
        <p class="text-on-surface">Enregistrer un reproducteur ici lui donne une <strong>identité</strong> (boucle, race, généalogie) — cela <strong>n'ajoute aucun animal</strong> à l'effectif : le sujet est déjà compté dans sa bande. Les entrées réelles (naissance, achat, don) se saisissent depuis <a href="{{ route('elevage.enregistrer-sujets') }}" class="text-info-blue underline font-semibold">Enregistrer des Sujets</a>.</p>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md mb-lg">
        <x-kpi-card label="Reproducteurs Enregistrés" icon="inventory_2" color="emerald" :value="$this->kpis['total']" />
        <x-kpi-card label="Présents" icon="check_circle" color="blue" :value="$this->kpis['presents']" />
        <x-kpi-card label="Femelles" icon="female" color="maize" :value="$this->kpis['femelles']" />
        <x-kpi-card label="Mâles" icon="male" color="forest" :value="$this->kpis['males']" />
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md flex flex-col md:flex-row items-stretch md:items-center gap-sm border-b border-outline-variant">
            <div class="relative flex-1 md:max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher un identifiant, une race..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
            </div>
            <select wire:model.live="speciesFilter" class="text-xs font-bold border border-outline-variant rounded-lg px-md py-2 bg-white outline-none">
                <option value="">Toutes les espèces</option>
                @foreach($this->speciesOptions as $espece)
                    <option value="{{ $espece->id }}">{{ $espece->label }}</option>
                @endforeach
            </select>
            <select wire:model.live="statusFilter" class="text-xs font-bold border border-outline-variant rounded-lg px-md py-2 bg-white outline-none">
                <option value="">Tous les statuts</option>
                <option value="actif">Actif</option>
                <option value="reforme">Réformé</option>
                <option value="vendu">Vendu</option>
                <option value="mort">Mort</option>
            </select>
        </div>

        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Identifiant</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Espèce</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Sexe</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Race</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Bande</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Cage</th>
                        <th class="px-md py-sm text-center text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->animals as $i => $animal)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                            <td data-label="Identifiant" class="px-md py-sm text-xs font-mono font-bold text-brand-emerald">
                                <a href="{{ route('elevage.animal-details', $animal) }}" class="hover:underline">{{ $animal->identifier }}</a>
                            </td>
                            <td data-label="Espèce" class="px-md py-sm text-xs">{{ $animal->species?->label ?? '—' }}</td>
                            <td data-label="Sexe" class="px-md py-sm text-xs">{{ $animal->sex === 'F' ? 'Femelle' : 'Mâle' }}</td>
                            <td data-label="Race" class="px-md py-sm text-xs">{{ $animal->breed ?: '—' }}</td>
                            <td data-label="Bande" class="px-md py-sm text-xs">{{ $animal->lot?->code ?: '—' }}</td>
                            <td data-label="Cage" class="px-md py-sm text-xs">{{ $animal->cage ?: '—' }}</td>
                            <td data-label="Statut" class="px-md py-sm text-center">
                                @if($animal->isPresent())
                                    <span class="text-[11px] font-bold px-sm py-0.5 rounded-full bg-brand-emerald/10 text-brand-emerald">Actif</span>
                                @else
                                    <span class="text-[11px] font-bold px-sm py-0.5 rounded-full bg-surface-zebra text-outline" title="{{ $animal->exit_reason }}">{{ ucfirst($animal->status) }}</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <a href="{{ route('elevage.animal-details', $animal) }}" class="text-brand-emerald hover:text-brand-forest p-1 inline-block" title="Consulter la fiche"><span class="material-symbols-outlined text-[18px]">visibility</span></a>
                                @can('manage-elevage')
                                    <button type="button" wire:click="editAnimal('{{ $animal->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                    @if($animal->isPresent())
                                        <button type="button" wire:click="openExit('{{ $animal->id }}')" class="text-error-deep hover:text-red-800 p-1" title="Enregistrer une sortie"><span class="material-symbols-outlined text-[18px]">logout</span></button>
                                    @endif
                                @endcan
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="8" class="px-md py-lg text-center text-outline">Aucun reproducteur enregistré pour ces critères.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-reproducteur" max-width="lg">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingId ? 'Modifier le Reproducteur' : 'Enregistrer un Reproducteur' }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-reproducteur' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveAnimal" class="grid grid-cols-1 sm:grid-cols-2 gap-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Identifiant (boucle) *</label>
                <input wire:model="identifier" type="text" placeholder="ex : LAP-2026-0143" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('identifier') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('identifier') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Espèce *</label>
                <select wire:model.live="species_id" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('species_id') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->speciesOptions as $espece)
                        <option value="{{ $espece->id }}">{{ $espece->label }}</option>
                    @endforeach
                </select>
                @error('species_id') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Bande d'appartenance</label>
                <select wire:model="lot_id" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                    <option value="">-- Aucune --</option>
                    @foreach($this->lotOptions as $lot)
                        <option value="{{ $lot->id }}">{{ $lot->code }}</option>
                    @endforeach
                </select>
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Sexe *</label>
                <select wire:model="sex" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                    <option value="F">Femelle</option>
                    <option value="M">Mâle</option>
                </select>
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Race</label>
                <input wire:model="breed" type="text" placeholder="ex : Néo-Zélandais Blanc" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Cage</label>
                <input wire:model="cage" type="text" placeholder="ex : C5" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date de Naissance</label>
                <input wire:model="birth_date" type="date" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('birth_date') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('birth_date') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date d'Entrée *</label>
                <input wire:model="entry_date" type="date" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('entry_date') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('entry_date') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="sm:col-span-2">
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Origine</label>
                <input wire:model="origin" type="text" placeholder="ex : Naissance interne (Lot LOT-CUNI-2026-002)" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div class="sm:col-span-2 flex justify-end gap-sm pt-md border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-reproducteur' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>

    <x-modal name="modal-sortie-reproducteur" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Enregistrer une Sortie</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-sortie-reproducteur' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <p class="text-xs text-outline mb-md">Le sujet cesse d'être présent et sa fiche le mentionne. <strong>L'effectif de la bande n'est pas modifié ici</strong> — c'est la fiche journalière qui fait foi sur les quantités, et le mouvement doit y être saisi.</p>
        <form wire:submit="confirmExit" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Motif de sortie *</label>
                <select wire:model="exitStatus" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                    <option value="reforme">Réforme</option>
                    <option value="vendu">Vente</option>
                    <option value="mort">Mortalité</option>
                </select>
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date de sortie *</label>
                <input wire:model="exit_date" type="date" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('exit_date') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('exit_date') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Précision</label>
                <input wire:model="exit_reason" type="text" placeholder="ex : Réforme pour âge" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div class="flex justify-end gap-sm pt-md border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-sortie-reproducteur' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-error-red text-white text-sm font-bold">Confirmer la Sortie</button>
            </div>
        </form>
    </x-modal>
</div>
