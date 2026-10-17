<div class="mt-md space-y-md">
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">badge</span>Registre des Employés
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Répertoire du personnel permanent de la ferme.</p>
        </div>
        <div class="flex items-center gap-xs">
            <button type="button" wire:click="exportEmployesPdf" wire:loading.attr="disabled" wire:target="exportEmployesPdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
            </button>
            <button type="button" wire:click="newEmployee" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
                <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouvel Employé
            </button>
        </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <x-kpi-card label="Employés actifs" icon="badge" color="emerald" :value="$this->kpis['employes_actifs']" />
        <x-kpi-card label="Nouveaux (année)" icon="person_add" color="blue" :value="$this->kpis['nouveaux_annee']" />
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md flex flex-col md:flex-row items-stretch md:items-center justify-between gap-sm border-b border-outline-variant">
            <div class="relative flex-1 md:max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
            </div>
            <select wire:model.live="statusFilter" class="border border-outline-variant rounded-lg text-xs px-sm py-2 bg-white w-full md:w-auto">
                <option value="">Tous les statuts</option>
                <option value="Actif">Actif</option>
                <option value="Congé">Congé</option>
                <option value="Suspendu">Suspendu</option>
            </select>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Nom</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Fonction</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date d'embauche</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Salaire</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->employees as $i => $employee)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Nom" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $employee->last_name }} {{ $employee->first_name }}</td>
                            <td data-label="Fonction" class="px-md py-sm text-xs">{{ $employee->position }}</td>
                            <td data-label="Date d'embauche" class="px-md py-sm text-xs">{{ $employee->hire_date?->format('d/m/Y') ?? '—' }}</td>
                            <td data-label="Salaire" class="px-md py-sm text-xs">{{ $employee->base_salary ? number_format($employee->base_salary, 0, ',', ' ') : '—' }}</td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($employee->status === 'actif')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Actif</span>
                                @elseif($employee->status === 'conge')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">Congé</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-bg text-error-deep border-error-deep/30">Suspendu</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button" wire:click="editEmployee('{{ $employee->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-employee-{{ $employee->id }}' })" class="text-error-deep hover:text-red-800 p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">archive</span></button>
                            </td>
                        </tr>
                        <x-modal-confirm-delete :name="'archive-employee-'.$employee->id" :item-label="$employee->last_name.' '.$employee->first_name" :action="'archiveEmployee(\''.$employee->id.'\')'" />
                    @empty
                        <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucun employé pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-create-registre-employes" max-width="lg">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingEmployeeId ? 'Modifier — Registre des Employés' : 'Nouvel Employé' }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-registre-employes' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveEmployee" class="space-y-md">
            <div class="grid grid-cols-2 gap-sm">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Prénom *</label>
                    <input wire:model="firstName" type="text" placeholder="ex : Bernadin" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('firstName') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('firstName') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nom *</label>
                    <input wire:model="lastName" type="text" placeholder="ex : ADJOVI" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('lastName') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('lastName') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Fonction *</label>
                <select wire:model="position" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('position') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    <option>Chef d'élevage</option>
                    <option>Comptable</option>
                    <option>Gardien</option>
                    <option>Vendeuse POS</option>
                    <option>Ouvrier agricole</option>
                </select>
                @error('position') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="grid grid-cols-2 gap-sm">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date d'embauche *</label>
                    <input wire:model="hireDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Salaire de base (FCFA)</label>
                    <input wire:model="baseSalary" type="number" min="0" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Statut</label>
                <select wire:model="status" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                    <option value="actif">Actif</option>
                    <option value="conge">Congé</option>
                    <option value="suspendu">Suspendu</option>
                </select>
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-registre-employes' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>
</div>
