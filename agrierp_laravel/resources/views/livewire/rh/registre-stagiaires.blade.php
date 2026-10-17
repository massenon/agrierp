<div class="mt-md space-y-md">
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">school</span>Registre des Stagiaires
            </h2>
            <p class="text-xs text-outline mt-xs">Suivi des stagiaires, frais de formation, absences et attestations — distinct du personnel permanent.</p>
        </div>
        <button type="button" wire:click="newInternship" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
            <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouveau Stagiaire
        </button>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <x-kpi-card label="Stagiaires Actifs" icon="school" color="emerald" :value="$this->kpis['stagiaires_actifs']" />
        <x-kpi-card label="Frais Collectés" icon="payments" color="blue" :value="number_format($this->kpis['frais_collectes'], 0, ',', ' ').' F'" />
        <x-kpi-card label="Frais en Attente" icon="pending" color="maize" :value="number_format($this->kpis['frais_en_attente'], 0, ',', ' ').' F'" />
        <x-kpi-card label="Attestations Émises" icon="workspace_premium" color="forest" :value="$this->kpis['attestations_emises']" />
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md flex flex-wrap items-center gap-sm">
        <div class="relative flex-1 min-w-[180px]">
            <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
            <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
        </div>
        <select wire:model.live="statusFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">Tous les statuts</option>
            <option value="En cours">En cours</option>
            <option value="Terminé">Terminé</option>
        </select>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Nom</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Établissement d'Origine</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Période</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Frais de Scolarité</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->internships as $i => $internship)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Nom" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $internship->last_name }} {{ $internship->first_name }}</td>
                            <td data-label="Établissement" class="px-md py-sm text-xs">{{ $internship->school }}</td>
                            <td data-label="Période" class="px-md py-sm text-xs">{{ $internship->start_date->format('d/m/Y') }} - {{ $internship->end_date?->format('d/m/Y') ?? '—' }}</td>
                            <td data-label="Frais" class="px-md py-sm text-xs text-right">
                                {{ $internship->monthly_fee ? number_format($internship->monthly_fee, 0, ',', ' ').' FCFA' : '—' }}
                                @if($internship->monthly_fee)
                                    @if($internship->fee_paid)
                                        <span class="inline-flex items-center px-1.5 py-[1px] rounded-full text-[9px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30 ml-1">Payé</span>
                                    @else
                                        <span class="inline-flex items-center px-1.5 py-[1px] rounded-full text-[9px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow ml-1">En attente</span>
                                    @endif
                                @endif
                            </td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($internship->is_active)
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">En cours</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-surface-zebra text-outline border-outline-variant">Terminé</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button" wire:click="editInternship('{{ $internship->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                <button type="button" wire:click="openAbsenceModal('{{ $internship->id }}')" class="text-brand-forest hover:text-brand-emerald p-1" title="Absences"><span class="material-symbols-outlined text-[18px]">event_busy</span></button>
                                @if(!$internship->is_active)
                                    <a href="{{ route('rh.personnel-stages-hub', ['tab' => 'attestations']) }}" class="text-brand-emerald hover:text-brand-forest p-1 inline-block" title="Générer attestation"><span class="material-symbols-outlined text-[18px]">workspace_premium</span></a>
                                @endif
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucun stagiaire pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-create-stagiaire" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingInternshipId ? 'Modifier le Stagiaire' : 'Nouveau Stagiaire' }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-stagiaire' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveInternship" class="space-y-md">
            <div class="grid grid-cols-2 gap-sm">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Prénom *</label>
                    <input wire:model="firstName" type="text" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('firstName') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('firstName') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nom *</label>
                    <input wire:model="lastName" type="text" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('lastName') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('lastName') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Établissement d'origine *</label>
                <input wire:model="school" type="text" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('school') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('school') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="grid grid-cols-2 gap-sm">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date de début *</label>
                    <input wire:model="startDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date de fin</label>
                    <input wire:model="endDate" type="date" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('endDate') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('endDate') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
            </div>
            <div class="grid grid-cols-2 gap-sm items-end">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Frais de stage (FCFA)</label>
                    <input wire:model="monthlyFee" type="number" min="0" placeholder="ex : 25000" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <label class="flex items-center gap-xs h-11">
                    <input wire:model="feePaid" type="checkbox" class="rounded border-outline-variant text-brand-emerald">
                    <span class="text-xs font-semibold text-brand-forest">Frais réglé</span>
                </label>
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-stagiaire' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>

    <x-modal name="modal-absence-stagiaire" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Absences — {{ $this->absenceInternship?->last_name }} {{ $this->absenceInternship?->first_name }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-absence-stagiaire' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveAbsence" class="space-y-md mb-md">
            <div class="grid grid-cols-2 gap-sm">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date *</label>
                    <input wire:model="absenceDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Motif</label>
                    <input wire:model="absenceReason" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
            </div>
            <button type="submit" class="w-full py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Ajouter l'absence</button>
        </form>
        <div class="space-y-xs max-h-52 overflow-y-auto">
            @forelse($this->absences as $absence)
                <div class="flex justify-between items-center text-xs border-b border-outline-variant/50 pb-1">
                    <span>{{ $absence->absence_date->format('d/m/Y') }}{{ $absence->reason ? ' — '.$absence->reason : '' }}</span>
                    <button type="button" wire:click="deleteAbsence('{{ $absence->id }}')" class="text-error-deep"><span class="material-symbols-outlined text-[16px]">close</span></button>
                </div>
            @empty
                <p class="text-xs text-outline text-center py-md">Aucune absence enregistrée.</p>
            @endforelse
        </div>
    </x-modal>
</div>
