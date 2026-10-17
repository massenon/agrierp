<div class="mt-md space-y-md">
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">schedule</span>Feuille de Pointage
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Suivi quotidien des heures de présence du personnel.</p>
        </div>
        <div class="flex items-center gap-xs">
            <button type="button" wire:click="exportPointagePdf" wire:loading.attr="disabled" wire:target="exportPointagePdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
            </button>
            <button type="button" wire:click="newRecord" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
                <span class="material-symbols-outlined text-[18px]">add_circle</span>Enregistrer un Pointage
            </button>
        </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <x-kpi-card label="Présents (jour)" icon="how_to_reg" color="emerald" :value="$this->kpis['presents']" />
        <x-kpi-card label="Absents" icon="person_off" color="red" :value="$this->kpis['absents']" />
        <x-kpi-card label="Retards" icon="timer" color="maize" :value="$this->kpis['retards']" />
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md flex flex-col md:flex-row items-stretch md:items-center justify-between gap-sm border-b border-outline-variant">
            <div class="relative flex-1 md:max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
            </div>
            <select wire:model.live="statusFilter" class="border border-outline-variant rounded-lg text-xs px-sm py-2 bg-white w-full md:w-auto">
                <option value="">Tous les statuts</option>
                <option value="Présent">Présent</option>
                <option value="Absent">Absent</option>
                <option value="Retard">Retard</option>
                <option value="Congé">Congé</option>
            </select>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Employé</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Arrivée</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Départ</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->records as $i => $record)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Employé" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $record->employee?->last_name }} {{ $record->employee?->first_name }}</td>
                            <td data-label="Date" class="px-md py-sm text-xs">{{ $record->attendance_date->format('d/m/Y') }}</td>
                            <td data-label="Arrivée" class="px-md py-sm text-xs">{{ $record->check_in ? substr($record->check_in, 0, 5) : '—' }}</td>
                            <td data-label="Départ" class="px-md py-sm text-xs">{{ $record->check_out ? substr($record->check_out, 0, 5) : '—' }}</td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($record->status === 'present')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Présent</span>
                                @elseif($record->status === 'absent')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-bg text-error-deep border-error-deep/30">Absent</span>
                                @elseif($record->status === 'retard')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">Retard</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-info-blue/10 text-info-blue border-info-blue/30">Congé</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button" wire:click="editRecord('{{ $record->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-pointage-{{ $record->id }}' })" class="text-error-deep hover:text-red-800 p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">archive</span></button>
                            </td>
                        </tr>
                        <x-modal-confirm-delete :name="'archive-pointage-'.$record->id" :item-label="($record->employee?->last_name ?? '').' '.($record->employee?->first_name ?? '').' — '.$record->attendance_date->format('d/m/Y')" :action="'archiveRecord(\''.$record->id.'\')'" />
                    @empty
                        <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucun pointage pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-create-feuille-pointage" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingRecordId ? 'Modifier le Pointage' : 'Enregistrer un Pointage' }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-feuille-pointage' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="savePointage" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Employé *</label>
                <select wire:model="employeeId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('employeeId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->employees as $employee)
                        <option value="{{ $employee->id }}">{{ $employee->last_name }} {{ $employee->first_name }}</option>
                    @endforeach
                </select>
                @error('employeeId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                <p class="text-[10px] text-outline mt-xs">Un seul pointage par employé et par jour — une nouvelle saisie sur la même date modifie le pointage existant.</p>
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date *</label>
                <input wire:model="attendanceDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div class="grid grid-cols-2 gap-sm">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Heure d'arrivée</label>
                    <input wire:model="checkIn" type="time" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Heure de départ</label>
                    <input wire:model="checkOut" type="time" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Statut *</label>
                <select wire:model="status" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('status') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    <option value="present">Présent</option>
                    <option value="absent">Absent</option>
                    <option value="retard">Retard</option>
                    <option value="conge">Congé</option>
                </select>
                @error('status') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="flex justify-end gap-sm pt-md border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-feuille-pointage' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>
</div>
