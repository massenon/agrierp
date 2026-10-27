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

                {{-- Signataires : ceux que la DURÉE appelle (ATT-2). Un champ vide reprend le modèle. --}}
                <details class="border border-outline-variant rounded-lg p-sm" @if($startDate) open @endif>
                    <summary class="text-[10px] font-bold text-brand-forest uppercase cursor-pointer select-none">
                        Signataires — {{ $this->palier === 'long' ? 'trois signataires (attestation de plus de '.($reglage[$personType]['seuil_signature_mois'] ?? 12).' mois)' : 'le promoteur seul (jusqu\'à '.($reglage[$personType]['seuil_signature_mois'] ?? 12).' mois)' }}
                    </summary>
                    <div class="mt-sm space-y-sm">
                        @forelse($this->signatairesRequis as $sig)
                        @php $cle = 'sig'.$sig['position']; @endphp
                        <div class="grid grid-cols-1 sm:grid-cols-3 gap-xs">
                            <div>
                                <label class="block text-[9px] text-brand-forest font-bold uppercase mb-xs">Intitulé</label>
                                <input wire:model.live.debounce.400ms="sigs.{{ $cle }}.titre" type="text" placeholder="{{ $sig['titre'] ?: '—' }}" class="w-full h-9 px-sm border border-outline-variant rounded-lg text-xs">
                            </div>
                            <div>
                                <label class="block text-[9px] text-brand-forest font-bold uppercase mb-xs">Nom</label>
                                <input wire:model.live.debounce.400ms="sigs.{{ $cle }}.nom" type="text" placeholder="{{ $sig['nom'] }}" class="w-full h-9 px-sm border border-outline-variant rounded-lg text-xs">
                            </div>
                            <div>
                                <label class="block text-[9px] text-brand-forest font-bold uppercase mb-xs">Fonction</label>
                                <input wire:model.live.debounce.400ms="sigs.{{ $cle }}.fonction" type="text" placeholder="{{ $sig['fonction'] }}" class="w-full h-9 px-sm border border-outline-variant rounded-lg text-xs">
                            </div>
                        </div>
                        @empty
                        <p class="text-[10px] text-outline">Aucun signataire n'est appelé par la règle de ce modèle (voir « Personnaliser les Modèles »).</p>
                        @endforelse
                        <p class="text-[10px] text-outline">Champs vides : le modèle s'applique. Qui signe, et à partir de quelle durée, se règle dans « Personnaliser les Modèles ».</p>
                    </div>
                </details>

                <button type="button" wire:click="generateAttestation" wire:loading.attr="disabled" wire:target="generateAttestation" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm flex items-center justify-center gap-xs disabled:opacity-50">
                    <span class="material-symbols-outlined text-[18px]">description</span>Générer l'Attestation
                </button>
            </div>

            {{-- ── Aperçu du certificat : même composition que le PDF (logo, filigrane, titre, corps, signataires). ── --}}
            <div class="bg-white border border-outline-variant rounded-lg p-lg relative overflow-hidden" style="min-height:480px;">
                <img src="{{ asset('assets/images/logo_ferme_ecole_officiel.png') }}" alt="" class="absolute pointer-events-none" style="left:50%; top:52%; width:62%; transform:translate(-50%,-50%); opacity:.12;">
                <div class="relative space-y-sm text-xs">

                    <div class="flex items-start gap-sm border-b border-outline-variant pb-sm">
                        <img src="{{ asset('assets/images/logo_ferme_ecole_officiel.png') }}" alt="Logo de la ferme" class="w-14 h-auto shrink-0">
                        <div class="flex-1 text-center">
                            <p class="font-black text-[#2e6b1a] text-sm tracking-wide">{{ config('attestation.nom') }}</p>
                            <p class="text-[8px] font-bold leading-tight">{{ implode(' ', config('attestation.activites')) }}</p>
                            <p class="text-[8px] leading-tight"><strong>Adresse</strong> : {{ config('attestation.adresse') }}</p>
                            <p class="text-[8px] leading-tight"><strong>Téléphone</strong> : {{ config('attestation.telephones') }}, <strong>RCCM</strong> : {{ config('attestation.rccm') }}</p>
                        </div>
                    </div>

                    <p class="text-right font-bold italic text-[9px]">{{ config('attestation.lieu') }}, le {{ \App\Services\AttestationService::dateLongue(now()) }}</p>
                    <p class="font-bold text-[9px]">{{ app(\App\Services\AttestationService::class)->prochainNumero() }}</p>

                    <p class="text-center font-bold text-brand-forest uppercase underline text-sm pt-sm">{{ $personType === 'employe' ? 'Attestation de Travail' : 'Attestation de Formation' }}</p>

                    <p class="leading-relaxed text-justify pt-xs">
                        @if($this->selectedPerson)
                            {{ $this->previewBody }}
                        @else
                            <span class="text-outline italic">Sélectionnez une personne pour prévisualiser l'attestation.</span>
                        @endif
                    </p>

                    @if(! empty($domaines))
                    <ul class="space-y-0.5 pl-md">
                        @foreach(\App\Services\AttestationService::DOMAINES_PUCES as $cle => $ligne)
                            @if(in_array($cle, $domaines))
                            <li class="flex gap-xs"><span>&#10146;</span><span>{{ $ligne }}</span></li>
                            @endif
                        @endforeach
                    </ul>
                    @endif

                    @if($this->selectedPerson && $this->previewAppreciation)
                        <p>{{ $this->previewAppreciation }}</p>
                    @endif

                    @if($this->selectedPerson)
                        <p>En foi de quoi, la présente attestation lui est délivrée pour servir et valoir ce que de droit.</p>
                    @endif

                    {{-- Signataires appelés par la durée : 3 (Examinateur, Président du Jury, Directeur Général) ou 1 (le promoteur). --}}
                    <div class="flex justify-between gap-sm pt-lg">
                        @foreach($this->signatairesRequis as $sig)
                        <div class="{{ count($this->signatairesRequis) === 1 ? 'ml-auto' : '' }} flex-1 max-w-[33%] text-right">
                            @if($sig['titre'] !== '')<p class="text-[9px] font-bold underline text-center mb-xs">{{ $sig['titre'] }}</p>@endif
                            <p class="font-bold text-[9px] leading-tight">{{ $sig['nom'] ?: '…' }}</p>
                            @if($sig['fonction'] !== '')<p class="text-[8px] leading-tight">{{ $sig['fonction'] }}</p>@endif
                        </div>
                        @endforeach
                    </div>
                    <p class="text-[8px] text-outline text-center pt-xs">Aperçu simplifié : le PDF reprend le modèle officiel (décor, filigrane, polices).</p>
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
                    <p class="text-[10px] text-outline mt-xs">Balises : [NOM], [POSTE], [CONTRAT], [DATE_DEBUT], [DATE_FIN], [DATE_DEBUT_LONGUE], [DATE_FIN_LONGUE], [DUREE], [DE_DUREE], [CIVILITE], [CIVILITE_LONGUE], [TITRE_NOM], [ACCORD_E]. **texte** s'imprime en gras.</p>
                </div>
                <button type="button" wire:click="saveTemplate('employe')" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">Enregistrer ce Modèle</button>
            </div>

            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
                <p class="text-xs font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">school</span>Modèle - Attestation de Formation (Stagiaire)</p>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Texte du certificat</label>
                    <textarea wire:model="tplStagiaireText" rows="6" class="w-full px-md py-sm border border-outline-variant rounded-lg text-xs"></textarea>
                    <p class="text-[10px] text-outline mt-xs">Balises : [NOM], [SPECIALITE], [ETABLISSEMENT], [DATE_DEBUT], [DATE_FIN], [DATE_DEBUT_LONGUE], [DATE_FIN_LONGUE], [DUREE], [DE_DUREE], [CIVILITE], [CIVILITE_LONGUE], [TITRE_NOM], [ACCORD_E], [DATE_NAISSANCE], [DATE_NAISSANCE_LONGUE], [LIEU_NAISSANCE]. **texte** s'imprime en gras.</p>
                </div>
                <button type="button" wire:click="saveTemplate('stagiaire')" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">Enregistrer ce Modèle</button>
            </div>
        </div>

        {{-- ATT-2 — Règle de signature selon la durée, par modèle. --}}
        <div class="grid grid-cols-1 gap-md mt-md">
            @foreach(['employe' => 'Attestation de Travail (Employé)', 'stagiaire' => 'Attestation de Formation (Stagiaire)'] as $type => $libelleModele)
            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md" dusk="reglage-{{ $type }}">
                <p class="text-xs font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">workspace_premium</span>Signataires et règle de signature — {{ $libelleModele }}</p>

                <div class="flex flex-wrap items-center gap-sm text-xs">
                    <span>Palier court : jusqu'à</span>
                    <input wire:model="reglage.{{ $type }}.seuil_signature_mois" type="number" min="1" max="120" dusk="seuil-{{ $type }}" class="w-20 h-9 px-sm border rounded-lg text-xs text-right {{ $errors->has('reglage.'.$type.'.seuil_signature_mois') ? 'is-invalid' : 'border-outline-variant' }}">
                    <span>mois <strong>inclus</strong> ; au-delà, palier long. Durée comptée de la date de début à la date de fin (à aujourd'hui sans date de fin).</span>
                </div>
                @error('reglage.'.$type.'.seuil_signature_mois') <p class="invalid-feedback">{{ $message }}</p> @enderror

                <div class="space-y-sm">
                    @foreach([1 => 'Directeur Général (le promoteur)', 2 => 'Examinateur', 3 => 'Président du Jury'] as $n => $role)
                    <div class="border border-outline-variant rounded-lg p-sm space-y-xs">
                        <p class="text-[10px] font-bold text-brand-forest uppercase">{{ $role }}</p>
                        <div class="grid grid-cols-1 sm:grid-cols-3 gap-xs">
                            <input wire:model="reglage.{{ $type }}.sig{{ $n }}_titre" type="text" placeholder="Intitulé imprimé (vide : aucun)" class="h-9 px-sm border border-outline-variant rounded-lg text-xs">
                            <input wire:model="reglage.{{ $type }}.sig{{ $n }}_nom" type="text" placeholder="Nom" class="h-9 px-sm border border-outline-variant rounded-lg text-xs">
                            <input wire:model="reglage.{{ $type }}.sig{{ $n }}_fonction" type="text" placeholder="Fonction" class="h-9 px-sm border border-outline-variant rounded-lg text-xs">
                        </div>
                        <div class="flex flex-wrap gap-md text-xs">
                            <label class="flex items-center gap-xs cursor-pointer"><input type="checkbox" wire:model="reglage.{{ $type }}.sig{{ $n }}_court" class="accent-brand-emerald">Signe le palier court</label>
                            <label class="flex items-center gap-xs cursor-pointer"><input type="checkbox" wire:model="reglage.{{ $type }}.sig{{ $n }}_long" class="accent-brand-emerald">Signe le palier long</label>
                        </div>
                    </div>
                    @endforeach
                </div>

                <div>
                    <label class="flex items-center gap-xs text-xs cursor-pointer mb-xs"><input type="checkbox" wire:model="reglage.{{ $type }}.appreciation_imprimee" class="accent-brand-emerald">Imprimer l'appréciation par défaut (modifiable à chaque émission)</label>
                    <textarea wire:model="reglage.{{ $type }}.appreciation_text" rows="2" placeholder="{{ $type === 'stagiaire' ? \App\Models\AttestationTemplate::APPRECIATION_STAGIAIRE : 'Aucune phrase standard' }}" class="w-full px-md py-sm border border-outline-variant rounded-lg text-xs"></textarea>
                    <p class="text-[10px] text-outline mt-xs">Vide : la phrase standard du modèle officiel. **texte** s'imprime en gras. Balises : [CIVILITE_LONGUE], [NOM], [TITRE_NOM], [ACCORD_E].</p>
                </div>

                <button type="button" wire:click="saveReglage('{{ $type }}')" dusk="enregistrer-reglage-{{ $type }}" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">Enregistrer la règle de signature</button>
            </div>
            @endforeach
        </div>
    @endif
</div>
