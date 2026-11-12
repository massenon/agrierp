<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">workspace_premium</span>{{ __('rh.titre_attestations') }}
        </h2>
        <p class="text-xs text-outline mt-xs">{{ __('rh.desc_attestations') }}</p>
    </div>

    <div class="flex items-center gap-xs border-b border-outline-variant mb-lg overflow-x-auto">
        <button type="button" wire:click="$set('tab', 'generer')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'generer' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">{{ __('rh.tab_generer_attestation') }}</button>
        <button type="button" wire:click="$set('tab', 'modeles')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'modeles' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">{{ __('rh.tab_personnaliser_modeles') }}</button>
    </div>

    @if($tab === 'generer')
        <div class="grid grid-cols-1 lg:grid-cols-[45%_55%] gap-md">
            {{-- ── Formulaire de génération ── --}}
            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">

                {{-- 1. Type de fiche --}}
                <p class="text-xs font-bold text-brand-forest uppercase">{{ __('rh.section_choix_fiche') }}</p>
                <div class="grid grid-cols-2 gap-sm">
                    <button type="button" wire:click="setPersonType('employe')" class="flex flex-col items-center gap-xs p-md rounded-lg border-2 font-bold text-xs {{ $personType === 'employe' ? 'border-brand-emerald bg-brand-emerald/5 text-brand-forest' : 'border-outline-variant text-outline' }}">
                        <span class="material-symbols-outlined text-[24px]">badge</span>{{ __('rh.option_employe_permanent') }}
                    </button>
                    <button type="button" wire:click="setPersonType('stagiaire')" class="flex flex-col items-center gap-xs p-md rounded-lg border-2 font-bold text-xs {{ $personType === 'stagiaire' ? 'border-brand-emerald bg-brand-emerald/5 text-brand-forest' : 'border-outline-variant text-outline' }}">
                        <span class="material-symbols-outlined text-[24px]">school</span>{{ __('rh.option_stagiaire_formation') }}
                    </button>
                </div>

                {{-- 2. Sélection de la personne --}}
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('rh.label_nom_personne') }}</label>
                    <select wire:model.live="personId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('personId') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">{{ __('rh.option_selectionner') }}</option>
                        @foreach($this->people as $person)
                            <option value="{{ $person->id }}">{{ $person->last_name }} {{ $person->first_name }}</option>
                        @endforeach
                    </select>
                    @error('personId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>

                <div class="grid grid-cols-2 gap-sm">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ $personType === 'employe' ? __('rh.label_poste_attestation') : __('rh.label_etablissement_attestation') }}</label>
                        <div class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center">{{ $personType === 'employe' ? $this->selectedPerson?->position : $this->selectedPerson?->school }}</div>
                    </div>
                    @if($personType === 'employe')
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('rh.label_type_contrat') }}</label>
                            <select wire:model.live="contractType" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                                <option>{{ __('rh.option_cdi') }}</option>
                                <option>{{ __('rh.option_cdd') }}</option>
                                <option>{{ __('rh.option_stage_conventionne') }}</option>
                            </select>
                        </div>
                    @endif
                </div>

                {{-- Civilité --}}
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('rh.label_civilite') }}</label>
                    <div class="flex gap-md">
                        <label class="flex items-center gap-xs text-sm cursor-pointer">
                            <input type="radio" wire:model.live="civilite" value="M." class="accent-brand-emerald">
                            <span>{{ __('rh.option_monsieur') }}</span>
                        </label>
                        <label class="flex items-center gap-xs text-sm cursor-pointer">
                            <input type="radio" wire:model.live="civilite" value="Mme" class="accent-brand-emerald">
                            <span>{{ __('rh.option_madame') }}</span>
                        </label>
                    </div>
                </div>

                <div class="grid grid-cols-2 gap-sm">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('rh.label_date_debut_attestation') }}</label>
                        <input wire:model.live="startDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('rh.label_date_fin_attestation') }}</label>
                        <input wire:model.live="endDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                </div>

                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('rh.label_date_attestation') }}</label>
                    <input wire:model.live="dateAttestation" type="date" dusk="date-attestation" max="{{ now()->format('Y-m-d') }}" class="w-full h-11 px-md border {{ $errors->has('dateAttestation') ? 'is-invalid' : 'border-outline-variant' }} rounded-lg text-sm">
                    @error('dateAttestation') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    <p class="text-[10px] text-outline mt-xs">{{ __('rh.info_date_attestation', ['lieu' => config('attestation.lieu')]) }}</p>
                </div>

                @if($startDate)
                <p class="text-[10px] text-outline -mt-sm">
                    {{ __('rh.label_duree_calculee') }}
                    <span class="font-semibold text-brand-forest">{{ $this->previewDuree ?: '—' }}</span>
                </p>
                @endif

                {{-- Domaines de formation --}}
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('rh.label_domaines_formation') }}</label>
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
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('rh.label_appreciation') }}</label>
                    <textarea wire:model.live="note" rows="3" placeholder="{{ __('rh.placeholder_appreciation') }}" class="w-full px-md py-sm border border-outline-variant rounded-lg text-sm"></textarea>
                </div>

                {{-- Signataires : ceux que la DURÉE appelle (ATT-2). Un champ vide reprend le modèle. --}}
                <details class="border border-outline-variant rounded-lg p-sm" @if($startDate) open @endif>
                    <summary class="text-[10px] font-bold text-brand-forest uppercase cursor-pointer select-none">
                        {{ __('rh.sig_reglage_titre') }} — {{ $this->palier === 'long' ? __('rh.sig_palier_long_desc', ['n' => $reglage[$personType]['seuil_signature_mois'] ?? 12]) : __('rh.sig_palier_court_desc', ['n' => $reglage[$personType]['seuil_signature_mois'] ?? 12]) }}
                    </summary>
                    <div class="mt-sm space-y-sm">
                        @forelse($this->signatairesRequis as $sig)
                        @php $cle = 'sig'.$sig['position']; @endphp
                        <div class="grid grid-cols-1 sm:grid-cols-3 gap-xs">
                            <div>
                                <label class="block text-[9px] text-brand-forest font-bold uppercase mb-xs">{{ __('rh.sig_intitule') }}</label>
                                <input wire:model.live.debounce.400ms="sigs.{{ $cle }}.titre" type="text" placeholder="{{ $sig['titre'] ?: '—' }}" class="w-full h-9 px-sm border border-outline-variant rounded-lg text-xs">
                            </div>
                            <div>
                                <label class="block text-[9px] text-brand-forest font-bold uppercase mb-xs">{{ __('rh.sig_nom_label') }}</label>
                                <input wire:model.live.debounce.400ms="sigs.{{ $cle }}.nom" type="text" placeholder="{{ $sig['nom'] }}" class="w-full h-9 px-sm border border-outline-variant rounded-lg text-xs">
                            </div>
                            <div>
                                <label class="block text-[9px] text-brand-forest font-bold uppercase mb-xs">{{ __('rh.sig_fonction_label') }}</label>
                                <input wire:model.live.debounce.400ms="sigs.{{ $cle }}.fonction" type="text" placeholder="{{ $sig['fonction'] }}" class="w-full h-9 px-sm border border-outline-variant rounded-lg text-xs">
                            </div>
                        </div>
                        @empty
                        <p class="text-[10px] text-outline">{{ __('rh.msg_aucun_signataire') }}</p>
                        @endforelse
                        <p class="text-[10px] text-outline">{{ __('rh.info_signataires_modele') }}</p>
                    </div>
                </details>

                <button type="button" wire:click="generateAttestation" wire:loading.attr="disabled" wire:target="generateAttestation" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm flex items-center justify-center gap-xs disabled:opacity-50">
                    <span class="material-symbols-outlined text-[18px]">description</span>{{ __('rh.bouton_generer_attestation') }}
                </button>
            </div>

            {{-- ── Aperçu du certificat : même composition que le PDF (logo, filigrane, titre, corps, signataires). ── --}}
            <div class="bg-white border border-outline-variant rounded-lg p-lg relative overflow-hidden" style="min-height:480px;">
                <img src="{{ asset('assets/images/logo_ferme_ecole_officiel.png') }}" alt="" class="absolute pointer-events-none" style="left:50%; top:52%; width:62%; transform:translate(-50%,-50%); opacity:.12;">
                <div class="relative space-y-sm text-xs">

                    {{-- En-tête du modèle officiel : logo à gauche (≈ 17 % de la largeur, pas plus), nom de la ferme en vert, activités
                         sur deux lignes, adresse, téléphone. ⚠️ Largeur en `style` : une classe Tailwind absente du CSS compilé
                         (`w-14` n'y était pas) rendait le logo à sa taille NATURELLE (476 px) et écrasait l'aperçu. --}}
                    <div class="flex items-start gap-sm">
                        <img src="{{ asset('assets/images/logo_ferme_ecole_officiel.png') }}" alt="Logo de la ferme" style="width:17%; max-width:96px; height:auto; flex-shrink:0;">
                        <div class="flex-1 text-center">
                            <p class="font-black text-[#2e6b1a] text-sm tracking-wide">{{ config('attestation.nom') }}</p>
                            @foreach(config('attestation.activites') as $ligne)
                            <p class="text-[8px] font-bold leading-tight">{{ $ligne }}</p>
                            @endforeach
                            <p class="text-[8px] leading-tight"><strong>Adresse</strong> : {{ config('attestation.adresse') }}</p>
                            <p class="text-[8px] leading-tight"><strong>Téléphone</strong> : {{ config('attestation.telephones') }}, <strong>RCCM</strong> : {{ config('attestation.rccm') }}</p>
                        </div>
                    </div>

                    <p class="text-right font-bold italic text-[9px]">{{ config('attestation.lieu') }}, le {{ \App\Services\AttestationService::dateLongue($dateAttestation ? \Illuminate\Support\Carbon::parse($dateAttestation) : now()) }}</p>
                    <p class="font-bold text-[9px]">{{ app(\App\Services\AttestationService::class)->prochainNumero() }}</p>

                    <p class="text-center font-bold text-brand-forest uppercase underline text-sm pt-sm">{{ $personType === 'employe' ? __('rh.attestation_de_travail') : __('rh.attestation_de_formation') }}</p>

                    <p class="leading-relaxed text-justify pt-xs">
                        @if($this->selectedPerson)
                            {{ $this->previewBody }}
                        @else
                            <span class="text-outline italic">{{ __('rh.msg_selectionner_personne') }}</span>
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
                        <p>{{ __('rh.attestation_en_foi') }}</p>
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
                    <p class="text-[8px] text-outline text-center pt-xs">{{ __('rh.apercu_simplifie') }}</p>
                </div>
            </div>
        </div>
    @endif

    @if($tab === 'modeles')
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-md">
            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
                <p class="text-xs font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">badge</span>{{ __('rh.modele_employe_titre') }}</p>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('rh.label_texte_certificat') }}</label>
                    <textarea wire:model="tplEmployeText" rows="6" class="w-full px-md py-sm border border-outline-variant rounded-lg text-xs"></textarea>
                    <p class="text-[10px] text-outline mt-xs">{{ __('rh.info_balises_employe') }}</p>
                </div>
                <button type="button" wire:click="saveTemplate('employe')" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">{{ __('rh.bouton_enregistrer_modele') }}</button>
            </div>

            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
                <p class="text-xs font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">school</span>{{ __('rh.modele_stagiaire_titre') }}</p>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('rh.label_texte_certificat') }}</label>
                    <textarea wire:model="tplStagiaireText" rows="6" class="w-full px-md py-sm border border-outline-variant rounded-lg text-xs"></textarea>
                    <p class="text-[10px] text-outline mt-xs">{{ __('rh.info_balises_stagiaire') }}</p>
                </div>
                <button type="button" wire:click="saveTemplate('stagiaire')" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">{{ __('rh.bouton_enregistrer_modele') }}</button>
            </div>
        </div>

        {{-- ATT-2 — Règle de signature selon la durée, par modèle. --}}
        <div class="grid grid-cols-1 gap-md mt-md">
            @foreach(['employe' => 'Attestation de Travail (Employé)', 'stagiaire' => 'Attestation de Formation (Stagiaire)'] as $type => $libelleModele)
            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md" dusk="reglage-{{ $type }}">
                <p class="text-xs font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">workspace_premium</span>{{ __('rh.sig_reglage_titre') }} — {{ $libelleModele }}</p>

                <div class="flex flex-wrap items-center gap-sm text-xs">
                    <span>{{ __('rh.sig_palier_court_intro') }}</span>
                    <input wire:model="reglage.{{ $type }}.seuil_signature_mois" type="number" min="1" max="120" dusk="seuil-{{ $type }}" class="w-20 h-9 px-sm border rounded-lg text-xs text-right {{ $errors->has('reglage.'.$type.'.seuil_signature_mois') ? 'is-invalid' : 'border-outline-variant' }}">
                    <span>mois <strong>{{ __('rh.sig_palier_mois_inclus') }}</strong> {{ __('rh.sig_palier_info') }}</span>
                </div>
                @error('reglage.'.$type.'.seuil_signature_mois') <p class="invalid-feedback">{{ $message }}</p> @enderror

                <div class="space-y-sm">
                    @foreach([1 => __('rh.sig_directeur_general'), 2 => __('rh.sig_examinateur'), 3 => __('rh.sig_president_jury')] as $n => $role)
                    <div class="border border-outline-variant rounded-lg p-sm space-y-xs">
                        <p class="text-[10px] font-bold text-brand-forest uppercase">{{ $role }}</p>
                        <div class="grid grid-cols-1 sm:grid-cols-3 gap-xs">
                            <input wire:model="reglage.{{ $type }}.sig{{ $n }}_titre" type="text" placeholder="{{ __('rh.sig_intitule_imprime') }}" class="h-9 px-sm border border-outline-variant rounded-lg text-xs">
                            <input wire:model="reglage.{{ $type }}.sig{{ $n }}_nom" type="text" placeholder="{{ __('rh.sig_nom_placeholder') }}" class="h-9 px-sm border border-outline-variant rounded-lg text-xs">
                            <input wire:model="reglage.{{ $type }}.sig{{ $n }}_fonction" type="text" placeholder="{{ __('rh.sig_fonction_placeholder') }}" class="h-9 px-sm border border-outline-variant rounded-lg text-xs">
                        </div>
                        <div class="flex flex-wrap gap-md text-xs">
                            <label class="flex items-center gap-xs cursor-pointer"><input type="checkbox" wire:model="reglage.{{ $type }}.sig{{ $n }}_court" class="accent-brand-emerald">{{ __('rh.sig_signe_court') }}</label>
                            <label class="flex items-center gap-xs cursor-pointer"><input type="checkbox" wire:model="reglage.{{ $type }}.sig{{ $n }}_long" class="accent-brand-emerald">{{ __('rh.sig_signe_long') }}</label>
                        </div>
                    </div>
                    @endforeach
                </div>

                <div>
                    <label class="flex items-center gap-xs text-xs cursor-pointer mb-xs"><input type="checkbox" wire:model="reglage.{{ $type }}.appreciation_imprimee" class="accent-brand-emerald">{{ __('rh.label_appreciation_imprimee') }}</label>
                    <textarea wire:model="reglage.{{ $type }}.appreciation_text" rows="2" placeholder="{{ $type === 'stagiaire' ? \App\Models\AttestationTemplate::APPRECIATION_STAGIAIRE : 'Aucune phrase standard' }}" class="w-full px-md py-sm border border-outline-variant rounded-lg text-xs"></textarea>
                    <p class="text-[10px] text-outline mt-xs">{{ __('rh.info_appreciation_vide') }}</p>
                </div>

                <button type="button" wire:click="saveReglage('{{ $type }}')" dusk="enregistrer-reglage-{{ $type }}" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">{{ __('rh.bouton_enregistrer_regle') }}</button>
            </div>
            @endforeach
        </div>
    @endif
</div>
