<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">workspace_premium</span>Attestations de Travail &amp; de Stage
        </h2>
        <p class="text-xs text-outline mt-xs">Personnalisez les modèles officiels, puis générez et téléchargez les attestations certifiées au format PDF.</p>
    </div>

    <div class="flex items-center gap-xs border-b border-outline-variant mb-lg overflow-x-auto">
        <button type="button" wire:click="$set('tab', 'generer')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'generer' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">Générer une Attestation</button>
        <button type="button" wire:click="$set('tab', 'modeles')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'modeles' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">Personnaliser les Modèles</button>
    </div>

    @if($tab === 'generer')
        <div class="grid grid-cols-1 lg:grid-cols-[45%_55%] gap-md">
            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
                <p class="text-xs font-bold text-brand-forest uppercase">1. Choix de la Fiche</p>
                <div class="grid grid-cols-2 gap-sm">
                    <button type="button" wire:click="setPersonType('employe')" class="flex flex-col items-center gap-xs p-md rounded-lg border-2 font-bold text-xs {{ $personType === 'employe' ? 'border-brand-emerald bg-brand-emerald/5 text-brand-forest' : 'border-outline-variant text-outline' }}">
                        <span class="material-symbols-outlined text-[24px]">badge</span>Employé Permanent
                    </button>
                    <button type="button" wire:click="setPersonType('stagiaire')" class="flex flex-col items-center gap-xs p-md rounded-lg border-2 font-bold text-xs {{ $personType === 'stagiaire' ? 'border-brand-emerald bg-brand-emerald/5 text-brand-forest' : 'border-outline-variant text-outline' }}">
                        <span class="material-symbols-outlined text-[24px]">school</span>Stagiaire en Formation
                    </button>
                </div>

                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nom de la personne *</label>
                    <select wire:model.live="personId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('personId') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">-- Sélectionner --</option>
                        @foreach($this->people as $person)
                            <option value="{{ $person->id }}">{{ $person->last_name }} {{ $person->first_name }}</option>
                        @endforeach
                    </select>
                    @error('personId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div class="grid grid-cols-2 gap-sm">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ $personType === 'employe' ? 'Poste' : 'Établissement' }}</label>
                        <div class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center">{{ $personType === 'employe' ? $this->selectedPerson?->position : $this->selectedPerson?->school }}</div>
                    </div>
                    @if($personType === 'employe')
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Type de Contrat</label>
                            <select wire:model.live="contractType" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                                <option>CDI</option>
                                <option>CDD</option>
                                <option>Stage conventionné</option>
                            </select>
                        </div>
                    @endif
                </div>
                <div class="grid grid-cols-2 gap-sm">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date de Début</label>
                        <input wire:model.live="startDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date de Fin</label>
                        <input wire:model.live="endDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Note d'Évaluation (optionnel)</label>
                    <textarea wire:model.live="note" rows="3" placeholder="Assiduité, rigueur, compétences acquises..." class="w-full px-md py-sm border border-outline-variant rounded-lg text-sm"></textarea>
                </div>
                <button type="button" wire:click="generateAttestation" wire:loading.attr="disabled" wire:target="generateAttestation" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm flex items-center justify-center gap-xs disabled:opacity-50">
                    <span class="material-symbols-outlined text-[18px]">description</span>Générer l'Attestation
                </button>
            </div>

            <div class="bg-white border border-outline-variant rounded-lg p-lg relative overflow-hidden" style="min-height:480px;">
                <div class="absolute inset-0 flex items-center justify-center pointer-events-none opacity-[0.05]">
                    <span class="material-symbols-outlined" style="font-size:220px;">agriculture</span>
                </div>
                <div class="relative space-y-md text-xs">
                    <div class="flex items-center justify-between border-b-2 border-brand-forest pb-md">
                        <div class="flex items-center gap-sm">
                            <span class="material-symbols-outlined text-brand-emerald" style="font-size:36px;">agriculture</span>
                            <div>
                                <p class="font-black text-brand-forest text-sm">FERME ÉCOLE OLOUWACHEGOUN</p>
                                <p class="text-[9px] text-outline">Attan-Ewé, Ikpinlè, Adja-Ouèrè, Bénin</p>
                                <p class="text-[9px] text-outline">RCCM : RB/PNO/22 A 33870</p>
                            </div>
                        </div>
                        <p class="font-bold text-brand-emerald text-sm uppercase">{{ $personType === 'employe' ? 'Attestation de Travail' : 'Attestation de Stage' }}</p>
                    </div>
                    <p class="text-center font-bold text-brand-forest uppercase tracking-wide pt-md">{{ $personType === 'employe' ? 'Attestation de Travail' : 'Attestation de Stage' }}</p>
                    <p class="leading-relaxed text-justify pt-sm">
                        @if($this->selectedPerson)
                            {{ $this->previewBody }}
                        @else
                            <span class="text-outline italic">Sélectionnez une personne pour prévisualiser l'attestation.</span>
                        @endif
                    </p>
                    @if($note)
                        <p class="text-outline italic">{{ $note }}</p>
                    @endif
                    <p class="pt-lg">Fait à Ikpinlè, le {{ now()->format('d/m/Y') }}.</p>
                    <div class="flex justify-end pt-xl">
                        <div class="text-center">
                            <p class="text-[10px] text-outline mb-8">Le Directeur Général</p>
                            <p class="font-bold text-brand-forest text-xs border-t border-outline-variant pt-xs">M. Olouchègoun</p>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    @endif

    @if($tab === 'modeles')
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-md">
            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
                <p class="text-xs font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">badge</span>Modèle - Attestation de Travail (Employé)</p>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Texte du certificat</label>
                    <textarea wire:model="tplEmployeText" rows="6" class="w-full px-md py-sm border border-outline-variant rounded-lg text-xs"></textarea>
                    <p class="text-[10px] text-outline mt-xs">Balises disponibles : [NOM], [POSTE], [CONTRAT], [DATE_DEBUT], [DATE_FIN]</p>
                </div>
                <button type="button" wire:click="saveTemplate('employe')" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">Enregistrer ce Modèle</button>
            </div>

            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
                <p class="text-xs font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">school</span>Modèle - Attestation de Stage (Stagiaire)</p>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Texte du certificat</label>
                    <textarea wire:model="tplStagiaireText" rows="6" class="w-full px-md py-sm border border-outline-variant rounded-lg text-xs"></textarea>
                    <p class="text-[10px] text-outline mt-xs">Balises disponibles : [NOM], [SPECIALITE], [ETABLISSEMENT], [DATE_DEBUT], [DATE_FIN]</p>
                </div>
                <button type="button" wire:click="saveTemplate('stagiaire')" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">Enregistrer ce Modèle</button>
            </div>
        </div>
    @endif
</div>
