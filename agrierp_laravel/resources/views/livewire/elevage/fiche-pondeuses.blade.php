<div>
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">egg</span>Fiches Pondeuses - Aviculture
            </h2>
            <p class="text-xs text-outline mt-xs">Suivi quotidien de la ponte et récolte d'œufs — transcription fidèle du registre de la ferme.</p>
        </div>
        <button type="button" wire:click="exportFichePdf" wire:loading.attr="disabled" wire:target="exportFichePdf" class="flex items-center gap-xs bg-white border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
        </button>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-md mb-lg">
        <x-kpi-card label="Effectif Pondeuses Vivantes" icon="pets" color="emerald" :value="number_format($this->kpis['effectif'], 0, ',', ' ')" />
        <x-kpi-card label="Taux de Ponte Moyen" icon="egg" color="blue" :value="number_format($this->kpis['taux_ponte_moyen'], 1, ',', ' ').' %'" />
        @if($this->kpis['stock_plateaux'] !== null)
            <x-kpi-card label="Stock Plateaux (30 œufs)" icon="grid_view" color="maize" :value="$this->kpis['stock_plateaux'].' Plateaux'" />
        @else
            <x-kpi-card label="Stock Plateaux (30 œufs)" icon="grid_view" color="maize" :pending="true" pending-since="qu'un produit &quot;Œufs de table&quot; existe au catalogue" />
        @endif
        <x-kpi-card label="Taux de Mortalité" icon="trending_down" color="red" :value="number_format($this->kpis['taux_mortalite_mois'], 1, ',', ' ').' %'" />
    </div>

    @if($this->lots->isEmpty())
        <div class="bg-white border border-outline-variant rounded-lg p-lg text-center mb-lg">
            <span class="material-symbols-outlined text-outline-variant text-[44px]">inbox</span>
            <p class="text-sm font-semibold text-on-surface mt-sm">Aucune bande active au stade Ponte pour le moment.</p>
            <a href="{{ route('elevage.bandes') }}" class="text-xs font-bold text-brand-emerald mt-sm inline-block">Créer une bande depuis Bandes &amp; Sujets →</a>
        </div>
    @else
    <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md lg:p-lg mb-lg">
        <div class="flex items-center justify-between border-b border-outline-variant pb-sm mb-md flex-wrap gap-xs">
            <div class="flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald">edit_note</span>
                <h3 class="font-bold text-base text-brand-forest">Saisie Journalière Ponte &amp; Cheptel</h3>
            </div>
            <div class="flex items-center gap-xs flex-wrap">
                @if($this->lots->count() > 1)
                    {{-- Ticket 15.47 (A11) : LA bande de la fiche, comme Lapins et Porcs. --}}
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

        <form wire:submit="saveDay" class="space-y-md">
            {{-- Ticket EX8 (EF12) : un jour d'un exercice clos se consulte, le formulaire est grisé (refus de saveDay : EX5).
                 Fusion EX7 + EX8 : le bandeau de lecture seule d'EX7 (même composant, même texte), pour l'exercice du jour. --}}
            <x-bandeau-lecture-seule :bandeau="$this->bandeauLectureSeule" action="passerALExerciceDeSaisie" />
            <fieldset @disabled($this->motifLectureSeule) class="space-y-md min-w-0">
            <x-transferts-du-jour :transferts="$this->transfertsDuJour" />
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Achats / Entrées du jour</label>
                    <input wire:model.live="achat" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nés / Transferts du jour</label>
                    <input wire:model.live="ne" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Ventes <span class="text-outline font-normal text-[9px]">(POS, réel)</span></label>
                    <input type="number" value="{{ $this->venteDuJour }}" readonly class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra text-outline cursor-not-allowed">
                </div>
            </div>

            <div class="bg-amber-500/10 border border-amber-500/30 rounded-lg p-md space-y-sm">
                <p class="text-xs font-bold text-amber-900 uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px] text-amber-700">egg</span>Workflow Récolte &amp; Stock d'Œufs</p>
                <div class="grid grid-cols-1 sm:grid-cols-4 gap-sm">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Total Œufs Récoltés (OR)</label>
                        <input wire:model.live="oeufsRecoltes" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold text-brand-forest">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Œufs Cassés / Fêlés (OF)</label>
                        <input wire:model.live="oeufsCasses" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Commercialisables (OR-OF)</label>
                        <div class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra font-bold text-brand-emerald flex items-center">{{ $this->commercialisables }}</div>
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Taux de Ponte Calculé (%)</label>
                        <div class="h-10 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center font-bold text-brand-emerald">{{ number_format($this->tauxPonteCalc, 1, ',', ' ') }} %</div>
                    </div>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-sm pt-xs">
                    <div class="bg-white border border-outline-variant rounded-lg p-sm text-xs font-semibold text-brand-forest">
                        Plateaux Nets Générés (30 œufs/plateau) : <strong class="text-brand-emerald text-sm">{{ $this->plateaux['plateaux'] }} Plateaux ({{ $this->plateaux['vrac'] }} œufs vrac)</strong>
                    </div>
                    <div class="bg-white border border-outline-variant rounded-lg p-sm text-xs font-semibold text-brand-forest">
                        @if($this->eggProduct)
                            Incrémentation Automatique du Stock : <strong class="text-brand-emerald">+{{ $this->plateaux['plateaux'] }} Plateaux ({{ $this->eggProduct->name }})</strong>
                        @else
                            <span class="text-outline">Aucun produit "Œufs de table" trouvé au catalogue — le stock ne sera pas incrémenté.</span>
                        @endif
                    </div>
                </div>
            </div>

            <div class="bg-error-bg/30 border border-error-red/20 rounded-lg p-sm">
                <p class="text-xs font-bold text-error-deep uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">skull</span>Morts par catégorie</p>
                @if($mortEnregistre !== null)
                    <p class="text-[11px] text-brand-forest bg-accent-yellow/20 border border-accent-yellow rounded-lg p-xs mb-xs" role="status">{{ $mortEnregistre }} mort(s) déjà enregistré(s) ce jour, sans répartition par catégorie : ils sont conservés tant qu'aucune répartition n'est saisie ci-dessous.</p>
                @endif
                <div class="grid grid-cols-3 gap-sm">
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Pondeuse / Repro</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('mortRepro', {{ max(0, $mortRepro - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="mortRepro" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('mortRepro', {{ $mortRepro + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Poulette</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('mortPoulette', {{ max(0, $mortPoulette - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="mortPoulette" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('mortPoulette', {{ $mortPoulette + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Poussin</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('mortPoussin', {{ max(0, $mortPoussin - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="mortPoussin" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('mortPoussin', {{ $mortPoussin + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                </div>
            </div>

            {{-- Ticket 15.56 — dons par catégorie : un don réduit l'effectif et sort du stock du produit de la bande. --}}
            <div class="bg-brand-emerald/5 border border-brand-emerald/20 rounded-lg p-sm">
                <p class="text-xs font-bold text-brand-emerald uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">redeem</span>Dons par catégorie</p>
                @if($donEnregistre !== null)
                    <p class="text-[11px] text-brand-forest bg-accent-yellow/20 border border-accent-yellow rounded-lg p-xs mb-xs" role="status">{{ $donEnregistre }} don(s) déjà enregistré(s) ce jour, sans répartition par catégorie : ils sont conservés tant qu'aucune répartition n'est saisie ci-dessous.</p>
                @endif
                <div class="grid grid-cols-3 gap-sm">
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Pondeuse / Repro</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('donRepro', {{ max(0, $donRepro - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="donRepro" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('donRepro', {{ $donRepro + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Poulette</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('donPoulette', {{ max(0, $donPoulette - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="donPoulette" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('donPoulette', {{ $donPoulette + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Poussin</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('donPoussin', {{ max(0, $donPoussin - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="donPoussin" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('donPoussin', {{ $donPoussin + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                </div>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-md bg-surface-zebra p-md rounded-lg border border-outline-variant">
                <div>
                    <p class="text-[10px] text-brand-forest font-bold uppercase">Effectif Final du Jour</p>
                    <p class="text-[10px] text-outline">= Effectif (J-1) + Achats/Nés − (Morts + Ventes + Dons)</p>
                    <div class="w-full h-10 px-md rounded-lg text-base font-black text-brand-emerald bg-white shadow-sm mt-1 flex items-center">{{ $this->effectifFinalCalc }}</div>
                </div>
                <div>
                    <p class="text-[10px] text-brand-forest font-bold uppercase">Taux de Mortalité du Jour (%)</p>
                    <p class="text-[10px] text-outline">= (Morts du Jour ÷ Effectif J-1) × 100</p>
                    <div class="h-10 px-md rounded-lg text-base font-black text-error-deep bg-white shadow-sm flex items-center mt-1">{{ number_format($this->mortalityRateCalc, 1, ',', ' ') }} %</div>
                </div>
            </div>

            {{-- Ticket 15.57 — sections du poste, désormais des deux côtés : rationnement par stade et pesée. --}}
            <x-ration-volaille :tableau="$this->rationnement" ligne-cle="du stade de la bande (Pondeuse)" />

            <div class="grid grid-cols-1 sm:grid-cols-3 gap-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Poids Général Pesé (g)</label>
                    <input wire:model.live="peseeTotal" type="number" min="0" placeholder="ex : 1800" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Taille Échantillon</label>
                    <div class="h-10 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center font-bold">{{ $this->effectifFinalCalc }}</div>
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Poids Moyen Constaté <span class="text-outline normal-case font-normal">(Poids Général ÷ Effectif Final)</span></label>
                    <div class="h-10 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center font-bold text-brand-emerald">
                        {{ $peseeTotal && $this->effectifFinalCalc > 0 ? round($peseeTotal / $this->effectifFinalCalc).' g' : '—' }}
                    </div>
                </div>
            </div>

            <div>
                <p class="text-xs font-bold text-brand-forest uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px] text-brand-emerald">inventory_2</span>Stock Œufs &amp; Plateaux (30) — Jour Sélectionné</p>
                <div class="grid grid-cols-2 sm:grid-cols-4 gap-sm">
                    <div class="bg-white border border-outline-variant rounded-lg p-sm text-center"><p class="text-[9px] text-outline font-bold uppercase">Stock Hier (SRH)</p><p class="text-sm font-bold text-brand-forest">{{ $this->stockToday['srh'] }}</p></div>
                    <div class="bg-white border border-outline-variant rounded-lg p-sm text-center"><p class="text-[9px] text-outline font-bold uppercase">Total Stock (TS)</p><p class="text-sm font-bold text-brand-forest">{{ $this->stockToday['ts'] }}</p></div>
                    <div class="bg-white border border-outline-variant rounded-lg p-sm text-center"><p class="text-[9px] text-outline font-bold uppercase">Sortie Vente (OS)</p><p class="text-sm font-bold text-outline">{{ $this->stockToday['os'] }}</p></div>
                    <div class="bg-brand-emerald/10 border border-brand-emerald/20 rounded-lg p-sm text-center"><p class="text-[9px] text-brand-forest font-bold uppercase">Stock Final</p><p class="text-sm font-bold text-brand-emerald">{{ $this->stockToday['final'] }}</p></div>
                </div>
            </div>

            <div class="border-t border-outline-variant pt-md">
                <p class="text-xs font-bold text-brand-forest uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-info-blue text-[18px]">vaccines</span>Traitements &amp; Rappels</p>
                @php $protocoleDuJour = $this->protocoleDuJour; @endphp
                @if($protocoleDuJour)
                    <x-prophylaxie-du-jour :protocole="$protocoleDuJour" />
                @endif
                <div class="mt-sm">
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Observations</label>
                    <input wire:model="observations" type="text" placeholder="ex : RAS" class="w-full h-10 px-md border border-outline-variant rounded-lg text-xs bg-white">
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
                        <th rowspan="2" class="sticky left-0 bg-surface-zebra px-2 py-2 text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Date / Jour</th>
                        <th colspan="4" class="px-2 py-2 text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Cheptel du Jour</th>
                        <th colspan="4" class="px-2 py-2 text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Suivi de la Ponte &amp; Récolte</th>
                        <th colspan="4" class="px-2 py-2 text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Stock Œufs &amp; Plateaux (30)</th>
                        <th rowspan="2" class="px-2 py-2 text-left text-[10px] text-outline font-bold uppercase">Traitements &amp; Rappels</th>
                    </tr>
                    <tr>
                        <th class="px-1.5 py-1 text-center text-[9px] text-outline font-bold">Eff. Début</th>
                        <th class="px-1.5 py-1 text-center text-[9px] text-outline font-bold">Morts</th>
                        <th class="px-1.5 py-1 text-center text-[9px] text-outline font-bold">Taux Mort %</th>
                        <th class="px-1.5 py-1 text-center text-[9px] text-outline font-bold border-r border-outline-variant">Eff. Fin</th>
                        <th class="px-1.5 py-1 text-center text-[9px] text-outline font-bold">Total (OR)</th>
                        <th class="px-1.5 py-1 text-center text-[9px] text-outline font-bold">Taux Ponte %</th>
                        <th class="px-1.5 py-1 text-center text-[9px] text-outline font-bold">Cassés (OF)</th>
                        <th class="px-1.5 py-1 text-center text-[9px] text-outline font-bold border-r border-outline-variant">Comm. (OR-OF)</th>
                        <th class="px-1.5 py-1 text-center text-[9px] text-outline font-bold">SRH</th>
                        <th class="px-1.5 py-1 text-center text-[9px] text-outline font-bold">TS</th>
                        <th class="px-1.5 py-1 text-center text-[9px] text-outline font-bold">OS</th>
                        <th class="px-1.5 py-1 text-center text-[9px] text-outline font-bold">Stock Final</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach($this->daysInMonth as $day)
                        @php
                            $dateStr = $this->debutMoisFiche()->addDays($day - 1)->format('Y-m-d');   // EX8 : le mois affiché
                            $entry = $this->monthlyEntries->get($dateStr);
                            $isToday = $dateStr === $selectedDate;
                            $comm = $entry ? max(0, ($entry->ponte_total ?? 0) - ($entry->ponte_casses ?? 0)) : null;
                            $tauxPonte = $entry && $entry->previousEffectif() > 0 ? round((($entry->ponte_total ?? 0) / $entry->previousEffectif()) * 100, 1) : null;
                        @endphp
                        <tr wire:click="loadDay('{{ $dateStr }}')" class="border-b border-outline-variant hover:bg-brand-emerald/5 cursor-pointer {{ $isToday ? 'bg-brand-emerald/10' : '' }}">
                            <td class="sticky left-0 bg-white px-2 py-1 font-bold border-r border-outline-variant">{{ \Carbon\Carbon::parse($dateStr)->format('d/m') }}</td>
                            <td class="px-1.5 py-1 text-center">{{ $entry ? $entry->previousEffectif() : '—' }}</td>
                            <td class="px-1.5 py-1 text-center {{ ($entry?->mort ?? 0) > 0 ? 'text-error-deep font-bold' : '' }}">{{ $entry?->mort ?? '—' }}</td>
                            <td class="px-1.5 py-1 text-center">{{ $entry ? number_format($entry->mortality_rate, 1) : '—' }}</td>
                            <td class="px-1.5 py-1 text-center font-bold border-r border-outline-variant">{{ $entry?->effectif_final ?? '—' }}</td>
                            <td class="px-1.5 py-1 text-center">{{ $entry?->ponte_total ?? '—' }}</td>
                            <td class="px-1.5 py-1 text-center">{{ $tauxPonte !== null ? number_format($tauxPonte, 1) : '—' }}</td>
                            <td class="px-1.5 py-1 text-center">{{ $entry?->ponte_casses ?? '—' }}</td>
                            <td class="px-1.5 py-1 text-center font-bold border-r border-outline-variant">{{ $comm ?? '—' }}</td>
                            <td class="px-1.5 py-1 text-center text-outline">{{ $isToday ? $this->stockToday['srh'] : '—' }}</td>
                            <td class="px-1.5 py-1 text-center text-outline">{{ $isToday ? $this->stockToday['ts'] : '—' }}</td>
                            <td class="px-1.5 py-1 text-center text-outline">{{ $isToday ? $this->stockToday['os'] : '—' }}</td>
                            <td class="px-1.5 py-1 text-center font-bold text-brand-emerald">{{ $isToday ? $this->stockToday['final'] : '—' }}</td>
                            <td class="px-2 py-1 text-left text-outline">{{ $this->traitementsDuJour($dateStr, $entry) }}</td>
                        </tr>
                    @endforeach
                </tbody>
            </table>
        </div>
        <p class="text-[10px] text-outline p-sm border-t border-outline-variant">Colonnes SRH/TS/OS/Stock Final : valeurs précises uniquement pour le jour sélectionné (reconstruction historique jour par jour non disponible avant le Sprint 6 — grand livre de mouvements de stock).</p>
    </div>
    @endif
</div>
