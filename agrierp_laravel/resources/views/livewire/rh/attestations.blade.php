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
            {{-- ── Formulaire de génération ── --}}
            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">

                {{-- 1. Type de fiche --}}
                <p class="text-xs font-bold text-brand-forest uppercase">1. Choix de la Fiche</p>
                <div class="grid grid-cols-2 gap-sm">
                    <button type="button" wire:click="setPersonType('employe')" class="flex flex-col items-center gap-xs p-md rounded-lg border-2 font-bold text-xs {{ $personType === 'employe' ? 'border-brand-emerald bg-brand-emerald/5 text-brand-forest' : 'border-outline-variant text-outline' }}">
                        <span class="material-symbols-outlined text-[24px]">badge</span>Employé Permanent
                    </button>
                    <button type="button" wire:click="setPersonType('stagiaire')" class="flex flex-col items-center gap-xs p-md rounded-lg border-2 font-bold text-xs {{ $personType === 'stagiaire' ? 'border-brand-emerald bg-brand-emerald/5 text-brand-forest' : 'border-outline-variant text-outline' }}">
                        <span class="material-symbols-outlined text-[24px]">school</span>Stagiaire en Formation
                    </button>
                </div>

                {{-- 2. Sélection de la personne --}}
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

                {{-- Civilité --}}
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Civilité</label>
                    <div class="flex gap-md">
                        <label class="flex items-center gap-xs text-sm cursor-pointer">
                            <input type="radio" wire:model.live="civilite" value="M." class="accent-brand-emerald">
                            <span>M. (Monsieur)</span>
                        </label>
                        <label class="flex items-center gap-xs text-sm cursor-pointer">
                            <input type="radio" wire:model.live="civilite" value="Mme" class="accent-brand-emerald">
                            <span>Mme (Madame)</span>
                        </label>
                    </div>
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

                @if($startDate)
                <p class="text-[10px] text-outline -mt-sm">
                    Durée calculée :
                    <span class="font-semibold text-brand-forest">{{ $this->previewDuree ?: '—' }}</span>
                </p>
                @endif

                {{-- Domaines de formation --}}
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Domaines de formation (optionnel)</label>
                    <div class="grid grid-cols-2 gap-xs">
                        @foreach(\App\Services\AttestationService::DOMAINES as $cle => $libelle)
                        <label class="flex items-center gap-xs text-xs cursor-pointer">
                            <input type="checkbox" wire:model.live="domaines" value="{{ $cle }}" class="accent-brand-emerald">
                            <span>{{ $libelle }}</span>
                        </label>
                        @endforeach
                    </div>
                </div>

                {{-- Appréciation --}}
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Appréciation (optionnel)</label>
                    <textarea wire:model.live="note" rows="3" placeholder="Assiduité, rigueur, compétences acquises..." class="w-full px-md py-sm border border-outline-variant rounded-lg text-sm"></textarea>
                </div>

                {{-- Signataires éditables --}}
                <details class="border border-outline-variant rounded-lg p-sm">
                    <summary class="text-[10px] font-bold text-brand-forest uppercase cursor-pointer select-none">Signataires (modifiables)</summary>
                    <div class="mt-sm space-y-sm">
                        @foreach([
                            ['sig2Titre', 'sig2Nom', "Signataire 1 (Examinateur)"],
                            ['sig3Titre', 'sig3Nom', "Signataire 2 (Président du Jury)"],
                            ['sig1Titre', 'sig1Nom', "Signataire 3 (Directeur Général)"],
                        ] as [$titreField, $nomField, $label])
                        <div class="grid grid-cols-2 gap-xs">
                            <div>
                                <label class="block text-[9px] text-brand-forest font-bold uppercase mb-xs">{{ $label }} — Titre</label>
                                <input wire:model.live="{{ $titreField }}" type="text" class="w-full h-9 px-sm border border-outline-variant rounded-lg text-xs">
                            </div>
                            <div>
                                <label class="block text-[9px] text-brand-forest font-bold uppercase mb-xs">{{ $label }} — Nom</label>
                                <input wire:model.live="{{ $nomField }}" type="text" class="w-full h-9 px-sm border border-outline-variant rounded-lg text-xs">
                            </div>
                        </div>
                        @endforeach
                    </div>
                </details>

                <button type="button" wire:click="generateAttestation" wire:loading.attr="disabled" wire:target="generateAttestation" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm flex items-center justify-center gap-xs disabled:opacity-50">
                    <span class="material-symbols-outlined text-[18px]">description</span>Générer l'Attestation
                </button>
            </div>

            {{-- ── Aperçu du certificat ── --}}
            <div class="bg-white border border-outline-variant rounded-lg p-lg relative overflow-hidden" style="min-height:480px;">
                <div class="absolute inset-0 flex items-center justify-center pointer-events-none opacity-[0.05]">
                    <span class="material-symbols-outlined" style="font-size:220px;">agriculture</span>
                </div>
                <div class="relative space-y-sm text-xs">

                    {{-- En-tête : ferme à gauche, lieu+date à droite --}}
                    <div class="flex items-start justify-between border-b-2 border-brand-forest pb-md gap-sm">
                        <div class="flex items-start gap-sm">
                            <span class="material-symbols-outlined text-brand-emerald" style="font-size:30px;">agriculture</span>
                            <div>
                                <p class="font-black text-brand-forest text-sm">FERME ÉCOLE OLOUWACHEGOUN</p>
                                <p class="text-[7px] text-brand-forest/70 font-bold leading-tight">MARAÎCHAGE - ÉLEVAGE - PISCICULTURE - AVICULTURE - TRANSFORMATION - GESTION D'ENTREPRISE</p>
                                <p class="text-[8px] text-outline leading-tight mt-0.5">Attan-Ewé, Ikpinlè, Adja-Ouèrè, Bénin</p>
                                <p class="text-[8px] text-outline">RCCM : RB/PNO/22 A 33870</p>
                            </div>
                        </div>
                        <div class="text-right shrink-0">
                            <p class="font-bold text-brand-forest text-[9px]">ATTAN-ÉWÉ, le {{ now()->day }} {{ ['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'][now()->month-1] }} {{ now()->year }}</p>
                            <p class="text-[9px] text-brand-forest/80 font-semibold mt-0.5">Réf. : {{ app(\App\Services\AttestationService::class)->prochainNumero() }}</p>
                        </div>
                    </div>

                    {{-- Titre --}}
                    <p class="text-center font-bold text-brand-forest uppercase tracking-wide pt-sm">{{ $personType === 'employe' ? 'Attestation de Travail' : 'Attestation de Formation' }}</p>

                    {{-- Domaines cochés --}}
                    @if(! empty($domaines))
                    <div class="flex flex-wrap gap-x-lg gap-y-xs py-xs border-y border-outline-variant">
                        @foreach(\App\Services\AttestationService::DOMAINES as $cle => $libelle)
                        <span class="flex items-center gap-xs text-[9px]">
                            <span class="inline-flex items-center justify-center w-3 h-3 border border-brand-forest {{ in_array($cle, $domaines) ? 'bg-brand-forest text-white' : '' }} text-[8px] font-bold">{{ in_array($cle, $domaines) ? '✓' : '' }}</span>
                            {{ $libelle }}
                        </span>
                        @endforeach
                    </div>
                    @endif

                    {{-- Corps --}}
                    <p class="leading-relaxed text-justify pt-xs">
                        @if($this->selectedPerson)
                            {{ $this->previewBody }}
                        @else
                            <span class="text-outline italic">Sélectionnez une personne pour prévisualiser l'attestation.</span>
                        @endif
                    </p>

                    @if($note)
                        <p class="text-outline italic">{{ $note }}</p>
                    @endif

                    {{-- 3 blocs de signature --}}
                    <div class="grid grid-cols-3 gap-sm pt-xl">
                        <div class="text-center">
                            <p class="text-[9px] text-outline mb-8">{{ $sig2Titre }}</p>
                            <p class="font-bold text-brand-forest text-[9px] border-t border-outline-variant pt-xs">{{ $sig2Nom ?: '…' }}</p>
                        </div>
                        <div class="text-center">
                            <p class="text-[9px] text-outline mb-8">{{ $sig3Titre }}</p>
                            <p class="font-bold text-brand-forest text-[9px] border-t border-outline-variant pt-xs">{{ $sig3Nom ?: '…' }}</p>
                        </div>
                        <div class="text-center">
                            <p class="text-[9px] text-outline mb-8">{{ $sig1Titre }}</p>
                            <p class="font-bold text-brand-forest text-[9px] border-t border-outline-variant pt-xs">{{ $sig1Nom ?: '…' }}</p>
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
                    <p class="text-[10px] text-outline mt-xs">Balises : [NOM], [POSTE], [CONTRAT], [DATE_DEBUT], [DATE_FIN], [DUREE], [CIVILITE], [TITRE_NOM], [ACCORD_E]</p>
                </div>
                <button type="button" wire:click="saveTemplate('employe')" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">Enregistrer ce Modèle</button>
            </div>

            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
                <p class="text-xs font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">school</span>Modèle - Attestation de Formation (Stagiaire)</p>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Texte du certificat</label>
                    <textarea wire:model="tplStagiaireText" rows="6" class="w-full px-md py-sm border border-outline-variant rounded-lg text-xs"></textarea>
                    <p class="text-[10px] text-outline mt-xs">Balises : [NOM], [SPECIALITE], [ETABLISSEMENT], [DATE_DEBUT], [DATE_FIN], [DUREE], [CIVILITE], [TITRE_NOM], [ACCORD_E], [DATE_NAISSANCE], [LIEU_NAISSANCE]</p>
                </div>
                <button type="button" wire:click="saveTemplate('stagiaire')" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">Enregistrer ce Modèle</button>
            </div>
        </div>
    @endif
</div>
