<div>
    <x-tab-page
        :tabs="[
            ['key' => 'registre', 'label' => 'Registre Vétérinaire', 'icon' => 'medical_information'],
            ['key' => 'calendrier', 'label' => 'Calendrier Vétérinaire', 'icon' => 'event_repeat'],
            ['key' => 'suivi', 'label' => 'Suivi Sanitaire', 'icon' => 'monitor_heart'],
        ]"
        :active="$tab">

        @if($tab === 'registre')
            <div class="mt-md space-y-md">
                <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm">
                    <div>
                        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[26px]">vaccines</span>Registre Vétérinaire</h2>
                        <p class="text-xs text-outline mt-xs">Carnet médical numérique : vaccinations, traitements et vermifuges du cheptel.</p>
                    </div>
                    <button type="button" wire:click="newSoin" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                        <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouveau Soin
                    </button>
                </div>

                <x-kpi-accordion title="Résumé sanitaire">
                    <x-kpi-card label="Interventions (mois)" icon="vaccines" color="emerald" :value="$this->kpisRegistre['interventions_mois']" />
                    <x-kpi-card label="Vaccinations planifiées" icon="event" color="blue" :value="$this->kpisRegistre['vaccinations_planifiees']" />
                    <x-kpi-card label="Animaux en quarantaine" icon="coronavirus" color="maize" :value="$this->kpisRegistre['en_quarantaine']" />
                    <x-kpi-card label="Coût sanitaire (mois)" icon="payments" color="red" :value="number_format($this->kpisRegistre['cout_sanitaire_mois'], 0, ',', ' ').' FCFA'" />
                </x-kpi-accordion>

                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="overflow-x-auto">
                        <table class="w-full rtable">
                            <thead class="bg-surface-zebra border-b border-outline-variant">
                                <tr>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Lot / Espèce</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Type d'action</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Produit</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Dose</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                @forelse($this->veterinaryRecords as $i => $rec)
                                    <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                        <td data-label="Date" class="px-md py-sm text-xs">{{ $rec->record_date->format('d/m/Y') }}</td>
                                        <td data-label="Lot" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $rec->lot?->code }} ({{ $rec->lot?->species?->label }})</td>
                                        <td data-label="Type" class="px-md py-sm text-xs">{{ $rec->action_type }}</td>
                                        <td data-label="Produit" class="px-md py-sm text-xs">{{ $rec->product_used ?? '—' }}</td>
                                        <td data-label="Dose" class="px-md py-sm text-xs">{{ $rec->dose ?? '—' }}</td>
                                        <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                            <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-soin-{{ $rec->id }}' })" class="text-outline hover:text-error-deep p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">delete</span></button>
                                        </td>
                                    </tr>
                                    <x-modal-confirm-delete :name="'archive-soin-'.$rec->id" :item-label="$rec->action_type.' — '.$rec->lot?->code" :action="'archiveSoin(\''.$rec->id.'\')'" />
                                @empty
                                    <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucun soin enregistré pour le moment.</td></tr>
                                @endforelse
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <x-modal name="modal-nouveau-soin" max-width="sm">
                <div class="flex items-center justify-between mb-md">
                    <h3 class="font-bold text-lg text-brand-forest">Nouveau Soin</h3>
                    <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-nouveau-soin' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
                </div>
                <form wire:submit="saveSoin" class="space-y-md">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Lot / Bande *</label>
                        <select wire:model="soinLotId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('soinLotId') ? 'is-invalid' : 'border-outline-variant' }}">
                            <option value="">-- Sélectionner --</option>
                            @foreach($this->activeLots as $lot)
                                <option value="{{ $lot->id }}">{{ $lot->code }} ({{ $lot->species?->label }})</option>
                            @endforeach
                        </select>
                        @error('soinLotId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date du Soin *</label>
                        <input wire:model="soinDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Type d'Action *</label>
                        <select wire:model="soinType" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('soinType') ? 'is-invalid' : 'border-outline-variant' }}">
                            <option value="">-- Sélectionner --</option>
                            <option>Vaccination</option><option>Traitement curatif</option><option>Vermifuge</option><option>Vitamines</option><option>Antistress</option><option>Hépato-protection</option>
                        </select>
                        @error('soinType') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div class="grid grid-cols-2 gap-sm">
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Produit Utilisé</label>
                            <input wire:model="soinProduit" type="text" placeholder="ex : Alfamec" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                        </div>
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Dose</label>
                            <input wire:model="soinDose" type="text" placeholder="ex : 0.5ml/lapin" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                        </div>
                    </div>
                    <div>
                        <label class="block text-[10px] text-error-deep font-bold uppercase mb-xs">Délai d'Attente / Rémanence (jours)</label>
                        <input wire:model="soinRemanence" type="number" min="0" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                        <p class="text-[9px] text-outline mt-xs">Si &gt; 0, la bande sera automatiquement bloquée à la vente (POS) pendant ce délai.</p>
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Vétérinaire / Animalier</label>
                        <input wire:model="soinVeterinaire" type="text" placeholder="ex : ADJOVI Bernadin" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Symptômes observés</label>
                        <textarea wire:model="soinSymptomes" rows="2" class="w-full px-md py-sm border border-outline-variant rounded-lg text-sm"></textarea>
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Coût (FCFA)</label>
                        <input wire:model="soinCout" type="number" min="0" placeholder="0" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                        <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-nouveau-soin' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                        <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
                    </div>
                </form>
            </x-modal>
        @endif

        @if($tab === 'calendrier')
            <div class="mt-md space-y-md">
                <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm">
                    <div>
                        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[26px]">event</span>Calendrier Vétérinaire</h2>
                        <p class="text-xs text-outline mt-xs">Planificateur de prophylaxie : lots d'élevage × échéances de soins (14 prochains jours).</p>
                    </div>
                    <button type="button" wire:click="newIntervention" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                        <span class="material-symbols-outlined text-[18px]">add_circle</span>Planifier une Intervention
                    </button>
                </div>

                <div class="flex items-center gap-lg mb-md flex-wrap text-xs">
                    <span class="flex items-center gap-xs"><span class="w-3 h-3 rounded-full inline-block bg-brand-emerald"></span>Effectué</span>
                    <span class="flex items-center gap-xs"><span class="w-3 h-3 rounded-full inline-block bg-accent-yellow"></span>Planifié</span>
                    <span class="flex items-center gap-xs"><span class="w-3 h-3 rounded-full inline-block bg-error-red"></span>En retard</span>
                    <span class="flex items-center gap-xs"><span class="w-3 h-3 rounded-full inline-block bg-info-blue"></span>Traitement en cours</span>
                </div>

                @if($this->activeLots->isEmpty())
                    <div class="bg-white border border-outline-variant rounded-lg p-lg text-center"><p class="text-sm text-outline">Aucune bande active pour le moment.</p></div>
                @else
                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="overflow-x-auto">
                        <table class="w-full text-xs border-collapse">
                            <thead class="bg-surface-zebra border-b border-outline-variant">
                                <tr>
                                    <th class="sticky left-0 bg-surface-zebra px-md py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant z-10">Lot / Bande</th>
                                    @foreach($this->ganttDays as $day)
                                        <th class="px-1 py-sm text-center text-[10px] font-bold text-outline w-10 border-l border-outline-variant {{ $day === now()->format('Y-m-d') ? 'bg-brand-emerald/10 text-brand-emerald font-extrabold' : '' }}">{{ \Carbon\Carbon::parse($day)->format('j/n') }}</th>
                                    @endforeach
                                </tr>
                            </thead>
                            <tbody>
                                @foreach($this->ganttRows as $i => $row)
                                    <tr class="{{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                        <td class="sticky left-0 bg-white px-md py-sm text-xs font-bold text-brand-forest border-r border-outline-variant whitespace-nowrap z-10">{{ $row['lot']->code }}</td>
                                        @foreach($this->ganttDays as $day)
                                            @php $event = $row['events']->get($day); @endphp
                                            <td class="p-1 border-l border-outline-variant text-center">
                                                @if($event)
                                                    @php
                                                        $colorMap = ['done' => 'bg-brand-emerald', 'planned' => 'bg-accent-yellow', 'late' => 'bg-error-red', 'inprogress' => 'bg-info-blue'];
                                                        $color = $colorMap[$event->display_status] ?? 'bg-accent-yellow';
                                                    @endphp
                                                    <button type="button"
                                                        @if($event->status !== 'done') wire:click="confirmAdministration('{{ $event->id }}')" @endif
                                                        title="{{ $event->task_type }}"
                                                        class="w-7 h-7 rounded-full mx-auto flex items-center justify-center text-white shadow-sm hover:scale-110 transition-transform {{ $color }}">
                                                        <span class="material-symbols-outlined" style="font-size:14px;">vaccines</span>
                                                    </button>
                                                @endif
                                            </td>
                                        @endforeach
                                    </tr>
                                @endforeach
                            </tbody>
                        </table>
                    </div>
                </div>
                @endif
            </div>

            <x-modal name="modal-planifier-intervention" max-width="sm">
                <div class="flex items-center justify-between mb-md">
                    <h3 class="font-bold text-lg text-brand-forest">Planifier une Intervention</h3>
                    <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-planifier-intervention' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
                </div>
                <form wire:submit="savePlan" class="space-y-md">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Lot / Bande *</label>
                        <select wire:model="planLotId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('planLotId') ? 'is-invalid' : 'border-outline-variant' }}">
                            <option value="">-- Sélectionner --</option>
                            @foreach($this->activeLots as $lot)
                                <option value="{{ $lot->id }}">{{ $lot->code }}</option>
                            @endforeach
                        </select>
                        @error('planLotId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Intervention *</label>
                        <input wire:model="planTaskType" type="text" placeholder="ex : Rappel Myxomatose" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('planTaskType') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('planTaskType') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date Prévue *</label>
                        <input wire:model="planDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                        <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-planifier-intervention' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                        <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Planifier</button>
                    </div>
                </form>
            </x-modal>
        @endif

        @if($tab === 'suivi')
            <div class="mt-md space-y-md">
                <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm">
                    <div>
                        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[26px]">monitor_heart</span>Suivi Sanitaire</h2>
                        <p class="text-xs text-outline mt-xs">Infirmerie d'élevage : suivi clinique des animaux en isolement, quarantaine ou observation.</p>
                    </div>
                    <button type="button" wire:click="newInfirmaryEntry" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                        <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouvelle Entrée Infirmerie
                    </button>
                </div>

                <x-kpi-accordion title="KPIs de l'Infirmerie">
                    <x-kpi-card label="En Quarantaine" icon="coronavirus" color="maize" :value="$this->kpisInfirmerie['en_quarantaine']" />
                    <x-kpi-card label="Guéris (mois)" icon="task_alt" color="emerald" :value="$this->kpisInfirmerie['gueris_mois']" />
                    <x-kpi-card label="Sous Traitement" icon="medication" color="blue" :value="$this->kpisInfirmerie['sous_traitement']" />
                    <x-kpi-card label="Décès (mois)" icon="heart_broken" color="red" :value="$this->kpisInfirmerie['deces_mois']" />
                </x-kpi-accordion>

                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="overflow-x-auto">
                        <table class="w-full rtable">
                            <thead class="bg-surface-zebra border-b border-outline-variant">
                                <tr>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date d'entrée</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Lot / Sujet</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Motif</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Niveau d'isolement</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                @forelse($this->infirmaryRecords as $i => $rec)
                                    <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                        <td data-label="Date" class="px-md py-sm text-xs">{{ $rec->entry_date->format('d/m/Y') }}</td>
                                        <td data-label="Lot / Sujet" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $rec->lot?->code }}{{ $rec->sujet_ref ? ' — '.$rec->sujet_ref : '' }}</td>
                                        <td data-label="Motif" class="px-md py-sm text-xs">{{ $rec->motif }}</td>
                                        <td data-label="Isolement" class="px-md py-sm text-xs">{{ $rec->isolation_level }}</td>
                                        <td data-label="Statut" class="px-md py-sm">
                                            @if($rec->status === 'en_cours')
                                                <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">En cours</span>
                                            @elseif($rec->status === 'reintegre')
                                                <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Réintégré</span>
                                            @else
                                                <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-bg text-error-deep border-error-deep/30">Décès</span>
                                            @endif
                                        </td>
                                        <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                            @if($rec->status === 'en_cours')
                                                <button type="button" wire:click="reintegrer('{{ $rec->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="Valider la guérison et réintégrer"><span class="material-symbols-outlined text-[18px]">settings_backup_restore</span></button>
                                                <button type="button" wire:click="declarerDeces('{{ $rec->id }}')" class="text-error-deep hover:text-red-800 p-1" title="Déclarer le décès"><span class="material-symbols-outlined text-[18px]">heart_broken</span></button>
                                            @else
                                                <span class="text-outline text-[11px]">Clôturé</span>
                                            @endif
                                        </td>
                                    </tr>
                                @empty
                                    <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucune entrée d'infirmerie pour le moment.</td></tr>
                                @endforelse
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <x-modal name="modal-nouvelle-entree-infirmerie" max-width="sm">
                <div class="flex items-center justify-between mb-md">
                    <h3 class="font-bold text-lg text-brand-forest">Nouvelle Entrée Infirmerie</h3>
                    <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-nouvelle-entree-infirmerie' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
                </div>
                <form wire:submit="saveInfirmaryEntry" class="space-y-md">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Lot / Bande *</label>
                        <select wire:model="infLotId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('infLotId') ? 'is-invalid' : 'border-outline-variant' }}">
                            <option value="">-- Sélectionner --</option>
                            @foreach($this->activeLots as $lot)
                                <option value="{{ $lot->id }}">{{ $lot->code }}</option>
                            @endforeach
                        </select>
                        @error('infLotId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Sujet (optionnel)</label>
                        <input wire:model="infSujetRef" type="text" placeholder="ex : #A-204" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Motif *</label>
                        <input wire:model="infMotif" type="text" placeholder="ex : Suspicion Newcastle" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('infMotif') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('infMotif') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Niveau d'Isolement *</label>
                        <select wire:model="infIsolation" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('infIsolation') ? 'is-invalid' : 'border-outline-variant' }}">
                            <option value="">-- Sélectionner --</option>
                            <option>Quarantaine stricte</option><option>Infirmerie</option><option>Simple surveillance</option>
                        </select>
                        @error('infIsolation') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date d'Entrée *</label>
                        <input wire:model="infDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                        <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-nouvelle-entree-infirmerie' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                        <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
                    </div>
                </form>
            </x-modal>
        @endif
    </x-tab-page>
</div>
