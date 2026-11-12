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
                        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[26px]">vaccines</span>{{ __('elevage.titre_soins_vaccins') }}</h2>
                        <p class="text-xs text-outline mt-xs">{{ __('elevage.desc_soins_vaccins') }}</p>
                    </div>
                    <button @lectureSeule type="button" wire:click="newSoin" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                        <span class="material-symbols-outlined text-[18px]">add_circle</span>{{ __('elevage.bouton_nouveau_soin') }}
                    </button>
                </div>

                <x-kpi-accordion title="Résumé sanitaire">
                    <x-kpi-card :label="__('elevage.kpi_interventions_mois')" icon="vaccines" color="emerald" :value="$this->kpisRegistre['interventions_mois']" />
                    <x-kpi-card :label="__('elevage.kpi_vaccinations_planifiees')" icon="event" color="blue" :value="$this->kpisRegistre['vaccinations_planifiees']" />
                    <x-kpi-card :label="__('elevage.kpi_animaux_quarantaine')" icon="coronavirus" color="maize" :value="$this->kpisRegistre['en_quarantaine']" />
                    <x-kpi-card :label="__('elevage.kpi_cout_sanitaire_mois')" icon="payments" color="red" :value="number_format($this->kpisRegistre['cout_sanitaire_mois'], 0, ',', ' ').' FCFA'" />
                </x-kpi-accordion>

                {{-- Ticket H11 — recherche et filtres du registre (ajouts du poste), filtrés par la requête. `x-datatable` ne
                     convient pas ici : il ne porte que la recherche (pas de listes de filtre) et aligne toutes les colonnes à
                     gauche, là où « Actions » est à droite. « Importer » / « Exporter PDF » sont inertes au poste : non construits. --}}
                <div class="bg-white border border-outline-variant rounded-lg p-md flex flex-wrap items-center gap-sm">
                    <div class="relative w-full sm:w-64">
                        <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                        <input wire:model.live.debounce.300ms="recherche" type="text" placeholder="{{ __('elevage.placeholder_rechercher_soin') }}" class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
                    </div>
                    <select wire:model.live="categorie" class="h-9 px-md border border-outline-variant rounded-lg text-xs bg-white">
                        <option value="">{{ __('elevage.filtre_toutes_categories') }}</option>
                        @foreach(\App\Livewire\Elevage\SoinsVaccinsHub::CATEGORIES_FILTRE as $categorie)
                            <option value="{{ $categorie }}">{{ $categorie }}</option>
                        @endforeach
                    </select>
                    <select wire:model.live="espece" class="h-9 px-md border border-outline-variant rounded-lg text-xs bg-white">
                        <option value="">{{ __('elevage.filtre_toutes_especes') }}</option>
                        @foreach(array_keys(\App\Livewire\Elevage\SoinsVaccinsHub::ESPECES_FILTRE) as $espece)
                            <option value="{{ $espece }}">{{ $espece }}</option>
                        @endforeach
                    </select>
                </div>

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
                                    {{-- Ticket H11 — colonne « Statut » du poste, après les six du Blade. --}}
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
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
                                            <button @lectureSeule type="button" x-on:click="$dispatch('open-modal', { name: 'archive-soin-{{ $rec->id }}' })" class="text-outline hover:text-error-deep p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">delete</span></button>
                                        </td>
                                        {{-- Un soin du registre est un soin ADMINISTRÉ (le planifié vit au calendrier) : « Effectué », comme au poste. --}}
                                        <td data-label="Statut" class="px-md py-sm"><span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">{{ __('elevage.statut_effectue') }}</span></td>
                                    </tr>
                                    <x-modal-confirm-delete :name="'archive-soin-'.$rec->id" :item-label="$rec->action_type.' — '.$rec->lot?->code" :action="'archiveSoin(\''.$rec->id.'\')'" />
                                @empty
                                    <tr><td colspan="7" class="px-md py-lg text-center text-outline">{{ $this->registreFiltre ? __('elevage.msg_soin_vide_filtre') : __('elevage.msg_aucun_soin') }}</td></tr>
                                @endforelse
                            </tbody>
                        </table>
                    </div>
                    <x-pagination :paginator="$this->veterinaryRecords" />
                </div>
            </div>

            <x-modal name="modal-nouveau-soin" max-width="sm">
                <div class="flex items-center justify-between mb-md">
                    <h3 class="font-bold text-lg text-brand-forest">{{ __('elevage.modal_titre_nouveau_soin') }}</h3>
                    <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-nouveau-soin' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
                </div>
                <form wire:submit="saveSoin" class="space-y-md">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_lot_bande') }}</label>
                        <select wire:model="soinLotId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('soinLotId') ? 'is-invalid' : 'border-outline-variant' }}">
                            <option value="">-- Sélectionner --</option>
                            @foreach($this->activeLots as $lot)
                                <option value="{{ $lot->id }}">{{ $lot->code }} ({{ $lot->species?->label }})</option>
                            @endforeach
                        </select>
                        @error('soinLotId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_date_soin') }}</label>
                        <input wire:model="soinDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_type_action') }}</label>
                        <select wire:model="soinType" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('soinType') ? 'is-invalid' : 'border-outline-variant' }}">
                            <option value="">-- Sélectionner --</option>
                            <option>{{ __('elevage.option_vaccination') }}</option><option>{{ __('elevage.option_traitement_curatif') }}</option><option>{{ __('elevage.option_vermifuge') }}</option><option>{{ __('elevage.option_vitamines') }}</option><option>{{ __('elevage.option_antistress') }}</option><option>{{ __('elevage.option_hepato_protection') }}</option>
                        </select>
                        @error('soinType') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div class="grid grid-cols-2 gap-sm">
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_produit_utilise') }}</label>
                            <input wire:model="soinProduit" type="text" placeholder="ex : Alfamec" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                        </div>
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_dose_soin') }}</label>
                            <input wire:model="soinDose" type="text" placeholder="ex : 0.5ml/lapin" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                        </div>
                    </div>
                    <div>
                        <label class="block text-[10px] text-error-deep font-bold uppercase mb-xs">{{ __('elevage.label_remanence') }}</label>
                        <input wire:model="soinRemanence" type="number" min="0" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                        <p class="text-[9px] text-outline mt-xs">{{ __('elevage.info_remanence') }}</p>
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_veterinaire') }}</label>
                        <input wire:model="soinVeterinaire" type="text" placeholder="ex : ADJOVI Bernadin" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_symptomes') }}</label>
                        <textarea wire:model="soinSymptomes" rows="2" class="w-full px-md py-sm border border-outline-variant rounded-lg text-sm"></textarea>
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_cout_fcfa') }}</label>
                        <input wire:model="soinCout" type="number" min="0" placeholder="0" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                        <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-nouveau-soin' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('elevage.bouton_annuler') }}</button>
                        <button @lectureSeule type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ __('elevage.bouton_enregistrer') }}</button>
                    </div>
                </form>
            </x-modal>
        @endif

        @if($tab === 'calendrier')
            <div class="mt-md space-y-md">
                <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm">
                    <div>
                        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[26px]">event</span>{{ __('elevage.titre_calendrier_veterinaire') }}</h2>
                        <p class="text-xs text-outline mt-xs">{{ __('elevage.desc_calendrier_veterinaire') }}</p>
                    </div>
                    <button @lectureSeule type="button" wire:click="newIntervention" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                        <span class="material-symbols-outlined text-[18px]">add_circle</span>{{ __('elevage.bouton_planifier_intervention') }}
                    </button>
                </div>

                <div class="flex items-center gap-lg mb-md flex-wrap text-xs">
                    <span class="flex items-center gap-xs"><span class="w-3 h-3 rounded-full inline-block bg-brand-emerald"></span>{{ __('elevage.legende_effectue') }}</span>
                    <span class="flex items-center gap-xs"><span class="w-3 h-3 rounded-full inline-block bg-accent-yellow"></span>{{ __('elevage.legende_planifie') }}</span>
                    <span class="flex items-center gap-xs"><span class="w-3 h-3 rounded-full inline-block bg-error-red"></span>{{ __('elevage.legende_en_retard') }}</span>
                    <span class="flex items-center gap-xs"><span class="w-3 h-3 rounded-full inline-block bg-info-blue"></span>{{ __('elevage.legende_traitement_en_cours') }}</span>
                </div>

                @if($this->activeLots->isEmpty())
                    <div class="bg-white border border-outline-variant rounded-lg p-lg text-center"><p class="text-sm text-outline">{{ __('elevage.msg_aucune_bande_active') }}</p></div>
                @else
                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="overflow-x-auto">
                        <table class="w-full text-xs border-collapse">
                            <thead class="bg-surface-zebra border-b border-outline-variant">
                                <tr>
                                    <th class="sticky left-0 bg-surface-zebra px-md py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant z-10">{{ __('elevage.col_lot_bande') }}</th>
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
                    <h3 class="font-bold text-lg text-brand-forest">{{ __('elevage.bouton_planifier_intervention') }}</h3>
                    <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-planifier-intervention' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
                </div>
                <form wire:submit="savePlan" class="space-y-md">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_lot_bande') }}</label>
                        <select wire:model="planLotId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('planLotId') ? 'is-invalid' : 'border-outline-variant' }}">
                            <option value="">-- Sélectionner --</option>
                            @foreach($this->activeLots as $lot)
                                <option value="{{ $lot->id }}">{{ $lot->code }}</option>
                            @endforeach
                        </select>
                        @error('planLotId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_intervention') }}</label>
                        <input wire:model="planTaskType" type="text" placeholder="ex : Rappel Myxomatose" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('planTaskType') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('planTaskType') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_date_prevue') }}</label>
                        <input wire:model="planDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                        <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-planifier-intervention' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('elevage.bouton_annuler') }}</button>
                        <button @lectureSeule type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ __('elevage.bouton_planifier') }}</button>
                    </div>
                </form>
            </x-modal>
        @endif

        @if($tab === 'suivi')
            <div class="mt-md space-y-md">
                <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm">
                    <div>
                        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[26px]">monitor_heart</span>{{ __('elevage.titre_suivi_sanitaire_infirmerie') }}</h2>
                        <p class="text-xs text-outline mt-xs">{{ __('elevage.desc_suivi_sanitaire') }}</p>
                    </div>
                    <button @lectureSeule type="button" wire:click="newInfirmaryEntry" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                        <span class="material-symbols-outlined text-[18px]">add_circle</span>{{ __('elevage.bouton_nouvelle_entree_infirmerie') }}
                    </button>
                </div>

                <x-kpi-accordion :title="__('elevage.kpi_infirmerie_titre')">
                    <x-kpi-card :label="__('elevage.kpi_en_quarantaine')" icon="coronavirus" color="maize" :value="$this->kpisInfirmerie['en_quarantaine']" />
                    <x-kpi-card :label="__('elevage.kpi_gueris_mois')" icon="task_alt" color="emerald" :value="$this->kpisInfirmerie['gueris_mois']" />
                    <x-kpi-card :label="__('elevage.kpi_sous_traitement')" icon="medication" color="blue" :value="$this->kpisInfirmerie['sous_traitement']" />
                    <x-kpi-card :label="__('elevage.kpi_deces_mois')" icon="heart_broken" color="red" :value="$this->kpisInfirmerie['deces_mois']" />
                </x-kpi-accordion>

                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="overflow-x-auto">
                        <table class="w-full rtable">
                            <thead class="bg-surface-zebra border-b border-outline-variant">
                                <tr>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('elevage.col_date_entree') }}</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('elevage.col_lot_sujet') }}</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('elevage.col_motif') }}</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('elevage.col_niveau_isolement') }}</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('elevage.col_statut') }}</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('elevage.col_actions') }}</th>
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
                                                <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">{{ __('elevage.statut_en_cours') }}</span>
                                            @elseif($rec->status === 'reintegre')
                                                <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">{{ __('elevage.statut_reintegre') }}</span>
                                            @else
                                                <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-bg text-error-deep border-error-deep/30">{{ __('elevage.statut_deces') }}</span>
                                            @endif
                                        </td>
                                        <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                            @if($rec->status === 'en_cours')
                                                <button @lectureSeule type="button" wire:click="reintegrer('{{ $rec->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="Valider la guérison et réintégrer"><span class="material-symbols-outlined text-[18px]">settings_backup_restore</span></button>
                                                <button @lectureSeule type="button" wire:click="declarerDeces('{{ $rec->id }}')" class="text-error-deep hover:text-red-800 p-1" title="Déclarer le décès"><span class="material-symbols-outlined text-[18px]">heart_broken</span></button>
                                            @else
                                                <span class="text-outline text-[11px]">{{ __('elevage.statut_cloture') }}</span>
                                            @endif
                                        </td>
                                    </tr>
                                @empty
                                    <tr><td colspan="6" class="px-md py-lg text-center text-outline">{{ __('elevage.msg_aucune_entree_infirmerie') }}</td></tr>
                                @endforelse
                            </tbody>
                        </table>
                    </div>
                    <x-pagination :paginator="$this->infirmaryRecords" />
                </div>
            </div>

            <x-modal name="modal-nouvelle-entree-infirmerie" max-width="sm">
                <div class="flex items-center justify-between mb-md">
                    <h3 class="font-bold text-lg text-brand-forest">{{ __('elevage.modal_titre_entree_infirmerie') }}</h3>
                    <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-nouvelle-entree-infirmerie' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
                </div>
                <form wire:submit="saveInfirmaryEntry" class="space-y-md">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_lot_bande') }}</label>
                        <select wire:model="infLotId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('infLotId') ? 'is-invalid' : 'border-outline-variant' }}">
                            <option value="">-- Sélectionner --</option>
                            @foreach($this->activeLots as $lot)
                                <option value="{{ $lot->id }}">{{ $lot->code }}</option>
                            @endforeach
                        </select>
                        @error('infLotId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_sujet_optionnel') }}</label>
                        <input wire:model="infSujetRef" type="text" placeholder="ex : #A-204" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_motif') }}</label>
                        <input wire:model="infMotif" type="text" placeholder="ex : Suspicion Newcastle" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('infMotif') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('infMotif') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_niveau_isolement') }}</label>
                        <select wire:model="infIsolation" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('infIsolation') ? 'is-invalid' : 'border-outline-variant' }}">
                            <option value="">-- Sélectionner --</option>
                            <option>{{ __('elevage.option_quarantaine_stricte') }}</option><option>{{ __('elevage.option_infirmerie') }}</option><option>{{ __('elevage.option_simple_surveillance') }}</option>
                        </select>
                        @error('infIsolation') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('elevage.label_date_entree') }}</label>
                        <input wire:model="infDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                        <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-nouvelle-entree-infirmerie' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('elevage.bouton_annuler') }}</button>
                        <button @lectureSeule type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ __('elevage.bouton_enregistrer') }}</button>
                    </div>
                </form>
            </x-modal>
        @endif
    </x-tab-page>
</div>
