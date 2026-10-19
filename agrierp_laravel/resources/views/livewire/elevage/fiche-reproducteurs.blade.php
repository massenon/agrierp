<div>
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">grid_view</span>Fiches Volailles - Reproducteurs, Poussins &amp; Goliath
            </h2>
            <p class="text-xs text-outline mt-xs">Suivi de la reproduction avicole, couvoir, incubation, éclosion, poussins et poulets de chair.</p>
        </div>
        <button type="button" wire:click="exportFichePdf" wire:loading.attr="disabled" wire:target="exportFichePdf" class="flex items-center gap-xs bg-white border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
        </button>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-md mb-lg">
        <x-kpi-card label="Effectif Total Vivant" icon="grid_view" color="emerald" :value="number_format($this->kpis['effectif_total'], 0, ',', ' ')" caption="Reproducteurs, Poussins & Goliath" />
        <x-kpi-card label="Taux d'Éclosion Couvoir" icon="egg" color="blue" :value="$this->kpis['taux_eclosion'] === null ? '—' : number_format($this->kpis['taux_eclosion'], 1, ',', ' ').' %'" caption="Ratio : Poussins Nés ÷ Œufs Couvés" />
        <x-kpi-card label="Poussins Nés (Éclosion)" icon="child_care" color="maize" :value="$this->kpis['poussins_nes']" caption="Cumul naissances au couvoir" />
        <x-kpi-card label="Taux de Mortalité" icon="trending_down" color="red" :value="number_format($this->kpis['taux_mortalite_mois'], 1, ',', ' ').' %'" caption="Seuil critique < 5%" />
    </div>

    @if($this->lots->isEmpty())
        <div class="bg-white border border-outline-variant rounded-lg p-lg text-center mb-lg">
            <span class="material-symbols-outlined text-outline-variant text-[44px]">inbox</span>
            <p class="text-sm font-semibold text-on-surface mt-sm">Aucune bande active (Reproducteurs/Goliath/Poussins) pour le moment.</p>
            <a href="{{ route('elevage.bandes') }}" class="text-xs font-bold text-brand-emerald mt-sm inline-block">Créer une bande depuis Bandes &amp; Sujets →</a>
        </div>
    @else
    <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md lg:p-lg mb-lg">
        <div class="flex items-center justify-between border-b border-outline-variant pb-sm mb-md flex-wrap gap-xs">
            <div class="flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald">edit_note</span>
                <h3 class="font-bold text-base text-brand-forest">Saisie Journalière Couvoir &amp; Suivi Chair</h3>
            </div>
            <div class="flex items-center gap-xs">
                <span class="text-xs text-outline font-semibold">Date :</span>
                <input type="date" wire:model.live="selectedDate" class="h-9 px-md border border-outline-variant rounded-lg text-xs font-bold text-brand-forest bg-surface-zebra cursor-pointer">
            </div>
        </div>

        <form wire:submit="saveDay" class="space-y-md">
            <x-transferts-du-jour :transferts="$this->transfertsDuJour" />
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Bande / Lot Concerné</label>
                    <select wire:model.live="selectedLotId" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold">
                        @foreach($this->lots as $lot)
                            <option value="{{ $lot->id }}">{{ $lot->code }} ({{ ucfirst($lot->stage) }} — {{ $lot->current_quantity }} têtes)</option>
                        @endforeach
                    </select>
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Achats du jour</label>
                    <input wire:model.live="achat" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Ventes <span class="text-outline font-normal text-[9px]">(POS, réel)</span></label>
                    <input type="number" value="{{ $this->venteDuJour }}" readonly class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra text-outline cursor-not-allowed">
                </div>
            </div>

            <div class="bg-amber-500/10 border border-amber-500/30 rounded-lg p-md space-y-sm">
                <p class="text-xs font-bold text-amber-900 uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px] text-amber-700">egg</span>Workflow Couvoir &amp; Éclosion (Incubation → Poussins Nés)</p>
                <div class="grid grid-cols-1 sm:grid-cols-3 gap-sm">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Œufs Couvés (Mis en incubation)</label>
                        <input wire:model.live="oeufsCouves" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Poussins Nés (Éclosion du jour)</label>
                        <input wire:model.live="poussinsNes" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold text-brand-emerald">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Taux d'Éclosion Calculé (%)</label>
                        <div class="h-10 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center font-bold text-brand-emerald">{{ number_format($this->eclosionRateCalc, 1, ',', ' ') }} %</div>
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
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Repro</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('mortRepro', {{ max(0, $mortRepro - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="mortRepro" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('mortRepro', {{ $mortRepro + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Poulet</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('mortPoulet', {{ max(0, $mortPoulet - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="mortPoulet" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('mortPoulet', {{ $mortPoulet + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
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
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Repro</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('donRepro', {{ max(0, $donRepro - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="donRepro" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('donRepro', {{ $donRepro + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Poulet</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('donPoulet', {{ max(0, $donPoulet - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="donPoulet" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('donPoulet', {{ $donPoulet + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
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
                    <p class="text-[10px] text-brand-forest font-bold uppercase">Effectif Final</p>
                    <p class="text-[10px] text-outline">= Effectif (J-1) + Achats/Poussins Nés − (Morts + Ventes + Dons)</p>
                    <div class="w-full h-10 px-md rounded-lg text-base font-black text-brand-emerald bg-white shadow-sm mt-1 flex items-center">{{ $this->effectifFinalCalc }}</div>
                </div>
                <div>
                    <p class="text-[10px] text-brand-forest font-bold uppercase">Taux de Mortalité du Jour (%)</p>
                    <p class="text-[10px] text-outline">= (Morts du Jour ÷ Effectif J-1) × 100</p>
                    <div class="h-10 px-md rounded-lg text-base font-black text-error-deep bg-white shadow-sm flex items-center mt-1">{{ number_format($this->mortalityRateCalc, 1, ',', ' ') }} %</div>
                </div>
            </div>

            {{-- Ticket 15.57 — rationnement par stade : section du poste, désormais des deux côtés. --}}
            <x-ration-volaille :tableau="$this->rationnement" ligne-cle="des reproducteurs" />

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Poids Général Pesé (g)</label>
                    <input wire:model.live="peseeTotal" type="number" min="0" placeholder="ex : 1800" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Poids Moyen Constaté <span class="text-outline normal-case font-normal">(Poids Général ÷ Effectif Final)</span></label>
                    <div class="h-10 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center font-bold text-brand-emerald">
                        {{ $peseeTotal && $this->effectifFinalCalc > 0 ? round($peseeTotal / $this->effectifFinalCalc).' g' : '—' }}
                    </div>
                </div>
            </div>

            <div class="border-t border-outline-variant pt-md">
                <p class="text-xs font-bold text-brand-forest uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-info-blue text-[18px]">vaccines</span>Traitements &amp; Prophylaxie</p>
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
        </form>
    </div>

    <div class="hidden lg:block bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden mb-lg">
        <div class="overflow-x-auto">
            <table class="w-full text-xs">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th rowspan="2" class="sticky left-0 bg-surface-zebra px-sm py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Date</th>
                        <th colspan="2" class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Couvoir</th>
                        <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Morts (total)</th>
                        <th rowspan="2" class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Effectif Final</th>
                        <th rowspan="2" class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Taux Mort %</th>
                        <th rowspan="2" class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase">Poids Général (g)</th>
                    </tr>
                    <tr>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Couvés</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Nés</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Repro+Poulet+Poussin</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach($this->daysInMonth as $day)
                        @php
                            $dateStr = now()->startOfMonth()->addDays($day - 1)->format('Y-m-d');
                            $entry = $this->monthlyEntries->get($dateStr);
                        @endphp
                        <tr wire:click="loadDay('{{ $dateStr }}')" class="border-b border-outline-variant hover:bg-brand-emerald/5 cursor-pointer {{ $dateStr === $selectedDate ? 'bg-brand-emerald/10' : '' }}">
                            <td class="sticky left-0 bg-white px-sm py-xs font-bold border-r border-outline-variant">{{ \Carbon\Carbon::parse($dateStr)->format('d/m') }}</td>
                            <td class="px-sm py-xs text-center border-r border-outline-variant">{{ $entry?->ponte_total ?? '—' }}</td>
                            <td class="px-sm py-xs text-center border-r border-outline-variant">{{ $entry?->ne ?? '—' }}</td>
                            <td class="px-sm py-xs text-center border-r border-outline-variant {{ ($entry?->mort ?? 0) > 0 ? 'text-error-deep font-bold' : '' }}">{{ $entry?->mort ?? '—' }}</td>
                            <td class="px-sm py-xs text-center font-bold border-r border-outline-variant">{{ $entry?->effectif_final ?? '—' }}</td>
                            <td class="px-sm py-xs text-center {{ $entry && $entry->mortality_rate > 0 ? 'text-error-deep font-bold' : '' }} border-r border-outline-variant">{{ $entry ? number_format($entry->mortality_rate, 1) : '—' }}</td>
                            <td class="px-sm py-xs text-right">{{ $entry?->poids_general_g ?? '—' }}</td>
                        </tr>
                    @endforeach
                </tbody>
            </table>
        </div>
        <p class="text-[10px] text-outline p-sm border-t border-outline-variant">La ventilation Repro/Poulet/Poussin des morts n'est pas conservée séparément après enregistrement (seul le total est persisté, conforme au schéma) — affichée en cumul dans l'historique.</p>
    </div>
    @endif
</div>
