<div>
    @if(!$moduleEnabled)
        <div class="bg-white border border-outline-variant rounded-lg p-xl text-center max-w-lg mx-auto mt-xl">
            <span class="material-symbols-outlined text-outline-variant text-[56px]">lock</span>
            <h2 class="text-lg font-bold text-on-surface mt-md">Module Héliciculture non activé</h2>
            <p class="text-sm text-outline mt-xs">Ce module est disponible mais désactivé par défaut. Un administrateur peut l'activer depuis Paramètres &gt; Modules Actifs.</p>
            <a href="{{ route('elevage.gestion') }}" class="inline-block mt-md text-xs font-bold text-brand-emerald hover:underline">← Retour à Gestion Élevage</a>
        </div>
    @else
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">bug_report</span>Fiches Escargots - Héliciculture
            </h2>
            <p class="text-xs text-outline mt-xs">Suivi mensuel du cheptel d'escargots — ponte en terre, éclosion des naissains et engraissement.</p>
        </div>
        <button type="button" wire:click="exportFichePdf" wire:loading.attr="disabled" wire:target="exportFichePdf" class="flex items-center gap-xs bg-white border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
        </button>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-md mb-lg">
        <x-kpi-card label="Effectif Total Vivant" icon="bug_report" color="emerald" :value="number_format($this->kpis['effectif_total'], 0, ',', ' ')" />
        <x-kpi-card label="Naissains Nés (mois)" icon="child_care" color="blue" :value="$this->kpis['naissains_mois']" />
        <x-kpi-card label="Taux d'Éclosion Naissains" icon="egg_alt" color="maize" :value="$this->kpis['taux_eclosion'] === null ? '—' : number_format($this->kpis['taux_eclosion'], 1, ',', ' ').' %'" />
        <x-kpi-card label="Taux de Mortalité" icon="trending_down" color="red" :value="number_format($this->kpis['taux_mortalite_mois'], 1, ',', ' ').' %'" />
    </div>

    @if($this->lots->isEmpty())
        <div class="bg-white border border-outline-variant rounded-lg p-lg text-center mb-lg">
            <span class="material-symbols-outlined text-outline-variant text-[44px]">inbox</span>
            <p class="text-sm font-semibold text-on-surface mt-sm">Aucune bande active en héliciculture pour le moment.</p>
            <a href="{{ route('elevage.bandes') }}" class="text-xs font-bold text-brand-emerald mt-sm inline-block">Créer une bande depuis Bandes &amp; Sujets →</a>
        </div>
    @else
    <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md lg:p-lg mb-lg">
        <div class="flex items-center justify-between border-b border-outline-variant pb-sm mb-md flex-wrap gap-xs">
            <div class="flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald">edit_note</span>
                <h3 class="font-bold text-base text-brand-forest">Saisie Journalière du Cheptel</h3>
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
            </div>
        </div>

        <form wire:submit="saveDay" class="space-y-md">
            <x-transferts-du-jour :transferts="$this->transfertsDuJour" />
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
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
                <p class="text-xs font-bold text-amber-900 uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px] text-amber-700">egg_alt</span>Workflow Ponte en Terre &amp; Éclosion des Naissains</p>
                <div class="grid grid-cols-1 sm:grid-cols-3 gap-sm">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Œufs Pondus (en terre)</label>
                        <input wire:model.live="oeufsTerre" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Naissains Nés (Éclosion)</label>
                        <input wire:model.live="naissainsNes" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold text-brand-emerald">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Taux d'Éclosion Naissains (%)</label>
                        <div class="h-10 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center font-bold text-brand-emerald">{{ $this->eclosionRateCalc === null ? '—' : number_format($this->eclosionRateCalc, 1, ',', ' ').' %' }}</div>
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
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Reproducteur (Bordé)</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('mortBorde', {{ max(0, $mortBorde - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="mortBorde" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('mortBorde', {{ $mortBorde + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Engraissement</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('mortEngraissement', {{ max(0, $mortEngraissement - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="mortEngraissement" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('mortEngraissement', {{ $mortEngraissement + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Naissain</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('mortNaissain', {{ max(0, $mortNaissain - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="mortNaissain" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('mortNaissain', {{ $mortNaissain + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
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
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Reproducteur (Bordé)</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('donBorde', {{ max(0, $donBorde - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="donBorde" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('donBorde', {{ $donBorde + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Engraissement</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('donEngraissement', {{ max(0, $donEngraissement - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="donEngraissement" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('donEngraissement', {{ $donEngraissement + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Naissain</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('donNaissain', {{ max(0, $donNaissain - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="donNaissain" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('donNaissain', {{ $donNaissain + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                </div>
            </div>

            <div class="grid grid-cols-3 gap-sm">
                <div>
                    <label class="block text-[9px] text-outline font-bold uppercase mb-xs">Naissains</label>
                    <input wire:model="effectifNaissains" type="number" min="0" class="w-full h-9 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
                <div>
                    <label class="block text-[9px] text-outline font-bold uppercase mb-xs">Engraissement</label>
                    <input wire:model="effectifEngraissement" type="number" min="0" class="w-full h-9 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
                <div>
                    <label class="block text-[9px] text-outline font-bold uppercase mb-xs">Bordés</label>
                    <input wire:model="effectifBordes" type="number" min="0" class="w-full h-9 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-md bg-surface-zebra p-md rounded-lg border border-outline-variant">
                <div>
                    <p class="text-[10px] text-brand-forest font-bold uppercase">Effectif Final du Jour</p>
                    <p class="text-[10px] text-outline">= Effectif (J-1) + Achats/Naissains − (Morts + Ventes + Dons)</p>
                    <div class="w-full h-10 px-md rounded-lg text-base font-black text-brand-emerald bg-white shadow-sm mt-1 flex items-center">{{ $this->effectifFinalCalc }}</div>
                </div>
                <div>
                    <p class="text-[10px] text-brand-forest font-bold uppercase">Taux de Mortalité du Jour (%)</p>
                    <p class="text-[10px] text-outline">= (Morts du Jour ÷ Effectif J-1) × 100</p>
                    <div class="h-10 px-md rounded-lg text-base font-black text-error-deep bg-white shadow-sm flex items-center mt-1">{{ number_format($this->mortalityRateCalc, 1, ',', ' ') }} %</div>
                </div>
            </div>

            <div class="border-t border-outline-variant pt-md">
                <p class="text-xs font-bold text-brand-forest uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px] text-brand-emerald">restaurant</span>Rationnement Farine Calcique &amp; Fourrage</p>
                <x-module-pending label="Le calcul du rationnement" since="qu'un barème officiel soit fourni pour l'héliciculture (absent de FeedRationStandards, ticket 2.7)" />
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Poids Général Pesé (g)</label>
                    <input wire:model.live="peseeTotal" type="number" min="0" placeholder="ex : 4500" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Poids Moyen Constaté <span class="text-outline normal-case font-normal">(Poids Général ÷ Effectif Final)</span></label>
                    <div class="h-10 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center font-bold text-brand-emerald">
                        {{ $peseeTotal && $this->effectifFinalCalc > 0 ? round($peseeTotal / $this->effectifFinalCalc).' g' : '—' }}
                    </div>
                </div>
            </div>

            <div class="border-t border-outline-variant pt-md">
                <p class="text-xs font-bold text-brand-forest uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-info-blue text-[18px]">thermostat</span>Entretien &amp; Hygrométrie</p>
                <x-module-pending label="Le suivi hygrométrique" since="à planifier — aucune table de mesures d'hygrométrie n'existe encore ; le ticket 3.11 (soins vétérinaires) ne la fournit pas" />
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
                        <th colspan="2" class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Entrées</th>
                        <th colspan="3" class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Sorties</th>
                        <th colspan="4" class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Effectif Final du Jour</th>
                        <th rowspan="2" class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Taux Mort %</th>
                        <th rowspan="2" class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Poids Général (g)</th>
                        <th rowspan="2" class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">Traitements &amp; Prophylaxie</th>
                    </tr>
                    <tr>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Achat</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Naissain Né</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Mort</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Vente</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Don</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold">Naissains</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold">Engraiss.</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold">Bordés</th>
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Total</th>
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
                            <td class="px-sm py-xs text-center border-r border-outline-variant">{{ $entry?->achat ?? '—' }}</td>
                            <td class="px-sm py-xs text-center border-r border-outline-variant">{{ $entry?->ne ?? '—' }}</td>
                            <td class="px-sm py-xs text-center border-r border-outline-variant {{ ($entry?->mort ?? 0) > 0 ? 'text-error-deep font-bold' : '' }}">{{ $entry?->mort ?? '—' }}</td>
                            <td class="px-sm py-xs text-center border-r border-outline-variant">{{ $entry?->vente ?? '—' }}</td>
                            <td class="px-sm py-xs text-center border-r border-outline-variant">{{ $entry?->don ?? '—' }}</td>
                            <td class="px-sm py-xs text-center">{{ $entry?->effectif_m ?? '—' }}</td>
                            <td class="px-sm py-xs text-center">{{ $entry?->effectif_f ?? '—' }}</td>
                            <td class="px-sm py-xs text-center">{{ $entry?->effectif_sevres ?? '—' }}</td>
                            <td class="px-sm py-xs text-center font-bold border-r border-outline-variant">{{ $entry?->effectif_final ?? '—' }}</td>
                            <td class="px-sm py-xs text-center {{ $entry && $entry->mortality_rate > 0 ? 'text-error-deep font-bold' : '' }} border-r border-outline-variant">{{ $entry ? number_format($entry->mortality_rate, 1) : '—' }}</td>
                            <td class="px-sm py-xs text-right">{{ $entry?->poids_general_g ?? '—' }}</td>
                            <td class="px-sm py-xs text-left text-outline">{{ $this->traitementsDuJour($dateStr, $entry) }}</td>
                        </tr>
                    @endforeach
                </tbody>
            </table>
        </div>
    </div>
    @endif
    @endif
</div>
