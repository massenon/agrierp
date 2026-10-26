<div>
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">pets</span>Fiches Porcs - Porciculture
            </h2>
            <p class="text-xs text-outline mt-xs">Fiche de suivi mensuel du cheptel porcin — engraissement, maternité et reproduction.</p>
        </div>
        <button type="button" wire:click="exportFichePdf" wire:loading.attr="disabled" wire:target="exportFichePdf" class="flex items-center gap-xs bg-white border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
        </button>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-md mb-lg">
        <x-kpi-card label="Effectif Porcins Vivants" icon="pets" color="emerald" :value="number_format($this->kpis['effectif_total'], 0, ',', ' ')" />
        <x-kpi-card label="Truies Gestantes / Verrats" icon="favorite" color="blue" :value="$this->kpis['truies'].' Truies / '.$this->kpis['verrats'].' Verrats'" />
        <x-kpi-card label="Porcelets sous Mère" icon="child_care" color="maize" :value="$this->kpis['porcelets_sous_mere']" />
        <x-kpi-card label="Taux de Mortalité" icon="trending_down" color="red" :value="number_format($this->kpis['taux_mortalite_mois'], 1, ',', ' ').' %'" />
    </div>

    @if($this->lots->isEmpty())
        <div class="bg-white border border-outline-variant rounded-lg p-lg text-center mb-lg">
            <span class="material-symbols-outlined text-outline-variant text-[44px]">inbox</span>
            <p class="text-sm font-semibold text-on-surface mt-sm">Aucune bande active en porciculture pour le moment.</p>
            <a href="{{ route('elevage.bandes') }}" class="text-xs font-bold text-brand-emerald mt-sm inline-block">Créer une bande depuis Bandes &amp; Sujets →</a>
        </div>
    @else
    <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md lg:p-lg mb-lg">
        <div class="flex items-center justify-between border-b border-outline-variant pb-sm mb-md flex-wrap gap-xs">
            <div class="flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald">edit_note</span>
                <h3 class="font-bold text-base text-brand-forest">Saisie Journalière du Cheptel Porcin</h3>
            </div>
            <div class="flex items-center gap-xs flex-wrap">
                @if($this->lots->count() > 1)
                    {{-- Ticket 15.42 : LA bande de la fiche. Toutes les requêtes (veille, jour chargé, enregistrement) portent sur elle. --}}
                    <span class="text-xs text-outline font-semibold">Bande :</span>
                    <select wire:model.live="bandeId" id="bande-fiche" class="h-9 px-md border border-outline-variant rounded-lg text-xs font-bold text-brand-forest bg-surface-zebra cursor-pointer">
                        @foreach($this->lots as $lotChoix)
                            <option value="{{ $lotChoix->id }}" @selected($lotChoix->id === $this->bande?->id)>{{ $lotChoix->code }}</option>
                        @endforeach
                    </select>
                @endif
                <span class="text-xs text-outline font-semibold">Date :</span>
                <input type="date" wire:model.live="selectedDate" class="h-9 px-md border border-outline-variant rounded-lg text-xs font-bold text-brand-forest bg-surface-zebra cursor-pointer">
                {{-- Ticket EX8 (EF12) : consulter un mois passé. --}}
                <x-mois-de-fiche :libelle="$this->libelleMois" :courant="$this->estMoisCourant" />
            </div>
        </div>

        @php $cat = $this->categoriesJour; $provende = $this->provendeCalculation; @endphp

        <form wire:submit="saveDay" class="space-y-md">
            {{-- Ticket EX8 (EF12) : un jour d'un exercice clos se consulte, le formulaire est grisé (refus de saveDay : EX5).
                 Fusion EX7 + EX8 : le bandeau de lecture seule d'EX7 (même composant, même texte), pour l'exercice du jour. --}}
            <x-bandeau-lecture-seule :bandeau="$this->bandeauLectureSeule" action="passerALExerciceDeSaisie" />
            <fieldset @disabled($this->motifLectureSeule) class="space-y-md min-w-0">
            <x-transferts-du-jour :transferts="$this->transfertsDuJour" />
            @if($cat['depart_requis'] && $cat['ancien'])
                {{-- D6 : les effectifs saisis à la main ne sont jamais repris ; le départ est déduit du stade de la bande (17/10/2026). --}}
                <div class="bg-accent-yellow/20 border border-accent-yellow rounded-lg p-sm text-xs text-brand-forest">
                    Cette bande porte déjà des effectifs par catégorie saisis à la main (fiche du {{ \Carbon\Carbon::parse($cat['ancien']['date'])->format('d/m/Y') }} :
                    Reproducteur {{ $cat['ancien']['categories']['repro'] }}, Porcelet {{ $cat['ancien']['categories']['sevre'] }}, Porc Marchand {{ $cat['ancien']['categories']['jeune'] }}).
                    Ils ne sont pas repris comme effectif de départ : l'effectif de départ ci-dessous est déduit du stade de la bande, corrigez-le si besoin avant d'enregistrer.
                </div>
            @endif

            <div class="grid grid-cols-1 sm:grid-cols-3 gap-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Achats du jour</label>
                    <input wire:model.live="achat" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nés (Mise bas porcelets)</label>
                    <input wire:model.live="ne" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Ventes <span class="text-outline font-normal text-[9px]">(POS, réel)</span></label>
                    <input type="number" value="{{ $this->venteDuJour }}" readonly class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra text-outline cursor-not-allowed">
                </div>
            </div>

            <div class="bg-error-bg/30 border border-error-red/20 rounded-lg p-sm">
                <p class="text-xs font-bold text-error-deep uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">skull</span>Morts par catégorie</p>
                <div class="grid grid-cols-3 gap-sm">
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Reproducteur (Truie/Verrat)</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('mortRepro', {{ max(0, $mortRepro - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="mortRepro" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('mortRepro', {{ $mortRepro + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Porc marchand / Engraiss.</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('mortMarchand', {{ max(0, $mortMarchand - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="mortMarchand" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('mortMarchand', {{ $mortMarchand + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Porcelet</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('mortPorcelet', {{ max(0, $mortPorcelet - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="mortPorcelet" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('mortPorcelet', {{ $mortPorcelet + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                </div>
            </div>

            <div class="bg-brand-emerald/5 border border-brand-emerald/20 rounded-lg p-sm">
                <p class="text-xs font-bold text-brand-emerald uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">redeem</span>Dons par catégorie</p>
                <div class="grid grid-cols-3 gap-sm">
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Reproducteur</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('donRepro', {{ max(0, $donRepro - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="donRepro" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('donRepro', {{ $donRepro + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Porc marchand</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('donMarchand', {{ max(0, $donMarchand - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="donMarchand" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('donMarchand', {{ $donMarchand + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Porcelet</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('donPorcelet', {{ max(0, $donPorcelet - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="donPorcelet" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('donPorcelet', {{ $donPorcelet + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                </div>
            </div>

            {{-- Passage de stade (QC3/D3 du 14-15/10/2026) : un FAIT saisi — nombre de sujets qui passent de Porcelet à Porc Marchand ce jour. HORS MAQUETTE, assumé. --}}
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Passage de stade (Porcelet → Porc Marchand) <span class="text-outline font-normal text-[9px] normal-case">(hors maquette)</span></label>
                    <input wire:model.live="passage" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
            </div>

            @if($cat['depart_requis'])
                {{-- Effectif de DÉPART (D4) : DÉDUIT du stade de la bande (AvecDepartAutomatique), corrigeable avant le premier enregistrement, puis verrouillé. --}}
                <div class="bg-brand-emerald/5 border border-brand-emerald/20 rounded-lg p-sm">
                    <p class="text-xs font-bold text-brand-emerald uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">edit_note</span>Effectif de départ par catégorie (déduit du stade de la bande)</p>
                    <p class="text-[10px] text-outline mb-xs">Effectif au DÉBUT du jour, avant les mouvements du jour, pré-rempli automatiquement depuis le stade de la bande. La somme des trois catégories doit égaler l'effectif total au début du jour ({{ $this->previousEffectif }}). Corrigez-le seulement pour une bande mixte ; il est verrouillé au premier enregistrement.</p>
                    <div class="grid grid-cols-3 gap-sm">
                        <div>
                            <label for="depart-repro" class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Reproducteur</label>
                            <input id="depart-repro" wire:model.live="departRepro" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border border-outline-variant rounded-lg bg-white">
                        </div>
                        <div>
                            <label for="depart-sevre" class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Porcelet</label>
                            <input id="depart-sevre" wire:model.live="departSevre" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border border-outline-variant rounded-lg bg-white">
                        </div>
                        <div>
                            <label for="depart-jeune" class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Porc Marchand</label>
                            <input id="depart-jeune" wire:model.live="departJeune" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border border-outline-variant rounded-lg bg-white">
                        </div>
                    </div>
                </div>
            @elseif($cat['depart'])
                <div class="bg-surface-zebra border border-outline-variant rounded-lg p-sm">
                    <p class="text-xs font-bold text-brand-forest uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">lock</span>Effectif de départ par catégorie (verrouillé)</p>
                    <p class="text-[10px] text-outline mb-xs">Effectif de départ fixé le {{ \Carbon\Carbon::parse($cat['depart_date'])->format('d/m/Y') }} (au début de ce jour).</p>
                    <div class="grid grid-cols-3 gap-sm">
                        <div>
                            <label for="depart-repro" class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Reproducteur</label>
                            <input id="depart-repro" type="number" value="{{ $cat['depart']['repro'] }}" disabled class="w-full h-9 text-center text-sm font-bold border border-outline-variant rounded-lg bg-surface-zebra text-outline cursor-not-allowed">
                        </div>
                        <div>
                            <label for="depart-sevre" class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Porcelet</label>
                            <input id="depart-sevre" type="number" value="{{ $cat['depart']['sevre'] }}" disabled class="w-full h-9 text-center text-sm font-bold border border-outline-variant rounded-lg bg-surface-zebra text-outline cursor-not-allowed">
                        </div>
                        <div>
                            <label for="depart-jeune" class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Porc Marchand</label>
                            <input id="depart-jeune" type="number" value="{{ $cat['depart']['jeune'] }}" disabled class="w-full h-9 text-center text-sm font-bold border border-outline-variant rounded-lg bg-surface-zebra text-outline cursor-not-allowed">
                        </div>
                    </div>
                    @if($cat['mode'] === 'avant_depart')
                        <p class="text-[10px] text-error-deep font-bold mt-xs">Jour antérieur à l'effectif de départ fixé le {{ \Carbon\Carbon::parse($cat['depart_date'])->format('d/m/Y') }} : les effectifs par catégorie ne sont pas calculés (—).</p>
                    @endif
                </div>
            @endif

            @if($cat['motif'])
                <div class="bg-error-bg border border-error-deep/30 rounded-lg p-sm text-xs text-error-deep font-bold" role="alert">{{ $cat['motif'] }}</div>
            @endif
            @if($cat['refus_passage'])
                <div class="bg-error-bg border border-error-deep/30 rounded-lg p-sm text-xs text-error-deep font-bold" role="alert">{{ $cat['refus_passage'] }}</div>
            @endif
            @if($this->avertissementMorts)
                <div class="bg-accent-yellow/20 border border-accent-yellow rounded-lg p-sm text-xs text-brand-forest" role="status">{{ $this->avertissementMorts }}</div>
            @endif
            @foreach($cat['avertissements'] as $avertissement)
                <div class="bg-accent-yellow/20 border border-accent-yellow rounded-lg p-sm text-xs text-brand-forest" role="status">{{ $avertissement }}</div>
            @endforeach
            @if($mortAncienTotal !== null || $donAncienTotal !== null)
                <div class="bg-accent-yellow/20 border border-accent-yellow rounded-lg p-sm text-xs text-brand-forest" role="status">
                    Fiche ancienne non ventilée par catégorie : {{ $mortAncienTotal ?? 0 }} mort(s) et {{ $donAncienTotal ?? 0 }} don(s) non ventilé(s) y sont enregistrés. Ventilez-les ci-dessus avant d'enregistrer.
                </div>
            @endif

            <div class="grid grid-cols-2 sm:grid-cols-4 gap-sm">
                <div>
                    <label class="block text-[9px] text-outline font-bold uppercase mb-xs">Verrats</label>
                    <input wire:model="effectifVerrats" type="number" min="0" class="w-full h-9 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
                <div>
                    <label class="block text-[9px] text-outline font-bold uppercase mb-xs">Truies Gestantes</label>
                    <input wire:model="effectifTruies" type="number" min="0" class="w-full h-9 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
                <div>
                    <label class="block text-[9px] text-outline font-bold uppercase mb-xs">Porcelets</label>
                    <input wire:model="effectifPorcelets" type="number" min="0" class="w-full h-9 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
                <div>
                    <label class="block text-[9px] text-outline font-bold uppercase mb-xs">Engraissement</label>
                    <input wire:model="effectifEngraissement" type="number" min="0" class="w-full h-9 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
            </div>

            <div class="border-t border-outline-variant pt-md space-y-md">
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-md bg-surface-zebra p-md rounded-lg border border-outline-variant">
                    <div>
                        <p class="text-[10px] text-brand-forest font-bold uppercase">Effectif Final du Jour (Calculé dynamique)</p>
                        <p class="text-[10px] text-outline">= Effectif (J-1) + Achats/Nés − (Morts + Ventes + Dons)</p>
                        <div class="w-full h-10 px-md rounded-lg text-base font-black text-brand-emerald bg-white shadow-sm mt-1 flex items-center">{{ $this->effectifFinalCalc }}</div>
                    </div>
                    <div>
                        <p class="text-[10px] text-brand-forest font-bold uppercase">Taux de Mortalité du Jour (%)</p>
                        <p class="text-[10px] text-outline">= (Morts du Jour ÷ Effectif J-1) × 100</p>
                        <div class="h-10 px-md rounded-lg text-base font-black text-error-deep bg-white shadow-sm flex items-center mt-1">{{ number_format($this->mortalityRateCalc, 1, ',', ' ') }} %</div>
                    </div>
                </div>

                <div>
                    <p class="text-xs font-bold text-brand-forest uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px] text-brand-emerald">restaurant</span>Rationnement &amp; Provende Servie par Stade Porcin (en Grammes g/j)</p>
                    {{-- D15 (décision client à confirmer) : la maquette dit « Porc Marchand », la donnée du barème dit « Jeune porc ». Libellé de la
                         maquette affiché ici ; le barème N'EST PAS renommé (rapprochement par clé stable `CategorieRationPorc`). --}}
                    <div class="bg-white border border-outline-variant rounded-lg overflow-hidden shadow-sm">
                        <table class="w-full text-xs">
                            <thead class="bg-surface-zebra text-outline border-b border-outline-variant">
                                <tr><th class="px-md py-xs text-left">Stade Physiologique</th><th class="px-md py-xs text-center">Effectif</th><th class="px-md py-xs text-center">Ration Normative</th><th class="px-md py-xs text-right">Provende Servie (g)</th></tr>
                            </thead>
                            <tbody class="divide-y divide-outline-variant/60">
                                <tr>
                                    <td class="px-md py-xs font-bold text-brand-forest">Porcelet</td>
                                    {{-- Ticket 15.42 : effectifs CALCULÉS (jamais saisis) — disabled, donc non focalisables ; « — » = inconnu, jamais 0. --}}
                                    <td class="px-md py-xs text-center"><input id="cat-eff-porcelet" type="text" inputmode="numeric" disabled value="{{ $provende['porcelet']['effectif'] ?? '—' }}" title="Calculé automatiquement : veille + nés − morts − dons Porcelet − passage de stade." class="w-16 h-8 text-center border border-outline-variant rounded text-xs font-bold bg-surface-zebra"></td>
                                    <td class="px-md py-xs text-center font-mono">{{ $provende['porcelet']['ration'] }} g/j</td>
                                    <td id="cat-prov-porcelet-g" class="px-md py-xs text-right font-mono font-bold text-brand-emerald">{{ $provende['porcelet']['total_g'] === null ? '—' : $provende['porcelet']['total_g'].' g' }}</td>
                                </tr>
                                <tr class="bg-surface-zebra">
                                    <td class="px-md py-xs font-bold text-brand-forest">Porc Marchand</td>
                                    <td class="px-md py-xs text-center"><input id="cat-eff-jeune" type="text" inputmode="numeric" disabled value="{{ $provende['jeune']['effectif'] ?? '—' }}" title="Calculé automatiquement : veille − ventes − morts − dons Porc Marchand + passage de stade." class="w-16 h-8 text-center border border-outline-variant rounded text-xs font-bold bg-white"></td>
                                    <td class="px-md py-xs text-center font-mono">{{ $provende['jeune']['ration'] }} g/j</td>
                                    <td id="cat-prov-jeune-g" class="px-md py-xs text-right font-mono font-bold text-brand-emerald">{{ $provende['jeune']['total_g'] === null ? '—' : $provende['jeune']['total_g'].' g' }}</td>
                                </tr>
                                <tr>
                                    <td class="px-md py-xs font-bold text-brand-forest">Reproducteur</td>
                                    <td class="px-md py-xs text-center"><input id="cat-eff-repro" type="text" inputmode="numeric" disabled value="{{ $provende['repro']['effectif'] ?? '—' }}" title="Calculé automatiquement : veille (ou départ) + achats − morts − dons Reproducteur." class="w-16 h-8 text-center border border-outline-variant rounded text-xs font-bold bg-surface-zebra"></td>
                                    <td class="px-md py-xs text-center font-mono text-brand-emerald font-bold">{{ number_format($provende['repro']['ration'], 0, ',', ' ') }} g/j ({{ number_format($provende['repro']['ration'] / 1000, 1) }} Kg)</td>
                                    <td id="cat-prov-repro-g" class="px-md py-xs text-right font-mono font-bold text-brand-emerald">{{ $provende['repro']['total_g'] === null ? '—' : $provende['repro']['total_g'].' g' }}</td>
                                </tr>
                            </tbody>
                            <tfoot class="bg-brand-emerald/10 font-bold text-brand-forest border-t border-brand-emerald/20">
                                <tr><td colspan="3" class="px-md py-xs uppercase text-[10px]">TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)</td><td id="day-total-provende-g" class="px-md py-xs text-right font-mono text-sm text-brand-emerald">{{ $provende['total_g'] === null ? '—' : $provende['total_g'].' g ('.$provende['total_kg'].' Kg)' }}</td></tr>
                            </tfoot>
                        </table>
                    </div>
                </div>

                <x-autonomie-alimentaire :autonomie="$this->feedAutonomy" filiere="porcine" />

                <div class="grid grid-cols-1 md:grid-cols-3 gap-md border-t border-outline-variant pt-md">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Poids Général Pesé (Kg)</label>
                        <input wire:model.live="peseeTotalKg" type="number" min="0" step="0.1"
                            placeholder="{{ $this->poidsMoyenEstimeKg !== null && $this->effectifFinalCalc > 0 ? '~'.number_format($this->poidsMoyenEstimeKg * $this->effectifFinalCalc, 1).' Kg (estimé)' : 'ex : 85' }}"
                            class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Effectif Final <span class="text-outline normal-case font-normal">(diviseur)</span></label>
                        <div class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra font-bold text-brand-forest flex items-center">{{ $this->effectifFinalCalc }}</div>
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Poids Moyen Constaté</label>
                        <div class="h-10 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center font-bold text-brand-emerald">
                            {{-- Ticket U12a : « — » sans pesée (comme Lapins), jamais « 0 Kg » — un zéro se lit comme un poids mesuré. --}}
                            {{ $peseeTotalKg && $this->effectifFinalCalc > 0 ? number_format($peseeTotalKg / $this->effectifFinalCalc, 1).' Kg' : '—' }}
                        </div>
                    </div>
                </div>
                @if($this->poidsMoyenEstimeKg !== null)
                    <p class="text-xs text-outline italic flex items-center gap-xs mt-xs">
                        <span class="material-symbols-outlined text-[14px]">trending_up</span>
                        Poids moyen estimé (GMQ) : <span class="font-bold text-brand-forest not-italic">{{ number_format($this->poidsMoyenEstimeKg, 2) }} Kg / animal</span>
                    </p>
                @endif

                <div class="border-t border-outline-variant pt-md">
                    <p class="text-xs font-bold text-brand-forest uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-info-blue text-[18px]">vaccines</span>Suivi Clinique &amp; Prophylaxie</p>
                    @php $protocoleDuJour = $this->protocoleDuJour; @endphp
                    @if($protocoleDuJour)
                        <x-prophylaxie-du-jour :protocole="$protocoleDuJour" />
                    @endif
                    <div class="mt-sm">
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Observations</label>
                        <input wire:model="observations" type="text" placeholder="ex : RAS" class="w-full h-10 px-md border border-outline-variant rounded-lg text-xs bg-white">
                    </div>
                </div>
            </div>

            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="submit" wire:loading.attr="disabled" wire:target="saveDay" class="px-md py-2 rounded-lg bg-brand-emerald hover:bg-brand-forest text-white text-xs font-bold shadow-sm disabled:opacity-50">
                    <span class="material-symbols-outlined text-[16px] align-middle mr-1">save</span>Enregistrer ce Jour
                </button>
            </div>
            </fieldset>
        </form>
    </div>

    <div class="hidden lg:block bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden mb-lg">
        <div class="overflow-x-auto">
            <table class="w-full text-xs">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th rowspan="2" class="sticky left-0 bg-surface-zebra px-sm py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Date</th>
                        <th colspan="2" class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Entrées</th>
                        <th colspan="3" class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Sorties</th>
                        <th colspan="5" class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Effectif Final du Jour</th>
                        <th rowspan="2" class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Taux Mort %</th>
                        <th rowspan="2" class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Poids Général (Kg)</th>
                        <th rowspan="2" class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">Traitements &amp; Prophylaxie</th>
                    </tr>
                    <tr>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Achat</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Né</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Mort</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Vente</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Don</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold">Truies Gest.</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold">Verrats</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold">Porcelets</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold">Engraiss.</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Total</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach($this->daysInMonth as $day)
                        @php
                            $dateStr = $this->debutMoisFiche()->addDays($day - 1)->format('Y-m-d');   // EX8 : le mois affiché
                            $entry = $this->monthlyEntries->get($dateStr);
                            $poidsKg = ($entry?->weight_sample_avg_g && $entry->effectif_final) ? round(($entry->weight_sample_avg_g * $entry->effectif_final) / 1000, 1) : null;
                        @endphp
                        <tr wire:click="loadDay('{{ $dateStr }}')" class="border-b border-outline-variant hover:bg-brand-emerald/5 cursor-pointer {{ $dateStr === $selectedDate ? 'bg-brand-emerald/10' : '' }}">
                            <td class="sticky left-0 bg-white px-sm py-xs font-bold border-r border-outline-variant">{{ \Carbon\Carbon::parse($dateStr)->format('d/m') }}</td>
                            <td class="px-sm py-xs text-center border-r border-outline-variant">{{ $entry?->achat ?? '—' }}</td>
                            <td class="px-sm py-xs text-center border-r border-outline-variant">{{ $entry?->ne ?? '—' }}</td>
                            <td class="px-sm py-xs text-center border-r border-outline-variant {{ ($entry?->mort ?? 0) > 0 ? 'text-error-deep font-bold' : '' }}">{{ $entry?->mort ?? '—' }}</td>
                            <td class="px-sm py-xs text-center border-r border-outline-variant">{{ $entry?->vente ?? '—' }}</td>
                            <td class="px-sm py-xs text-center border-r border-outline-variant">{{ $entry?->don ?? '—' }}</td>
                            <td class="px-sm py-xs text-center">{{ $entry?->effectif_f ?? '—' }}</td>
                            <td class="px-sm py-xs text-center">{{ $entry?->effectif_m ?? '—' }}</td>
                            <td class="px-sm py-xs text-center">{{ $entry?->effectif_sevres ?? '—' }}</td>
                            <td class="px-sm py-xs text-center">{{ $entry?->effectif_smeres ?? '—' }}</td>
                            <td class="px-sm py-xs text-center font-bold border-r border-outline-variant">{{ $entry?->effectif_final ?? '—' }}</td>
                            <td class="px-sm py-xs text-center {{ $entry && $entry->mortality_rate > 0 ? 'text-error-deep font-bold' : '' }} border-r border-outline-variant">{{ $entry ? number_format($entry->mortality_rate, 1) : '—' }}</td>
                            <td class="px-sm py-xs text-right">{{ $poidsKg ?? '—' }}</td>
                            <td class="px-sm py-xs text-left text-outline">{{ $this->traitementsDuJour($dateStr, $entry) }}</td>
                        </tr>
                    @endforeach
                </tbody>
            </table>
        </div>
    </div>
    @endif
</div>
