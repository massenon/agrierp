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
            <a wire:navigate href="{{ route('elevage.bandes') }}" class="text-xs font-bold text-brand-emerald mt-sm inline-block">Créer une bande depuis Bandes &amp; Sujets →</a>
        </div>
    @else
    <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md lg:p-lg mb-lg">
        <div class="flex items-center justify-between border-b border-outline-variant pb-sm mb-md flex-wrap gap-xs">
            <div class="flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald">edit_note</span>
                <h3 class="font-bold text-base text-brand-forest">Saisie Journalière Couvoir &amp; Suivi Chair</h3>
            </div>
            <div class="flex items-center gap-xs flex-wrap">
                <span class="text-xs text-outline font-semibold">Date :</span>
                <input type="date" wire:model.live="selectedDate" class="h-9 px-md border border-outline-variant rounded-lg text-xs font-bold text-brand-forest bg-surface-zebra cursor-pointer">
                {{-- Ticket EX8 (EF12) : consulter un mois passé. --}}
                <x-mois-de-fiche :libelle="$this->libelleMois" :courant="$this->estMoisCourant" />
            </div>
        </div>

        @php $cat = $this->categoriesJour; $ventesJ = $this->ventesDuJour; @endphp

        <form wire:submit="saveDay" class="space-y-md">
            {{-- Ticket EX8 (EF12) : un jour d'un exercice clos se consulte, le formulaire est grisé (refus de saveDay : EX5).
                 Fusion EX7 + EX8 : le bandeau de lecture seule d'EX7 (même composant, même texte), pour l'exercice du jour. --}}
            <x-bandeau-lecture-seule :bandeau="$this->bandeauLectureSeule" action="passerALExerciceDeSaisie" />
            <fieldset @disabled($this->motifLectureSeule) class="space-y-md min-w-0">
            <x-transferts-du-jour :transferts="$this->transfertsDuJour" />
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Bande / Lot Concerné</label>
                    <select wire:model.live="selectedLotId" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold">
                        @foreach($this->lots as $lot)
                            <option value="{{ $lot->id }}">{{ $lot->code }} ({{ $lot->libelleStade() }} — {{ $lot->current_quantity }} têtes)</option>
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
                    {{-- Ticket VOL-1 : la caisse range chaque vente dans la catégorie du PRODUIT vendu (lecture seule). --}}
                    <p id="ventes-par-categorie" class="text-[10px] text-outline mt-xs">Reproducteur {{ $ventesJ['repro'] }} · Jeune {{ $ventesJ['jeune'] }} · Poussin {{ $ventesJ['sevre'] }}</p>
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
                        <div class="h-10 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center font-bold text-brand-emerald">{{ $this->eclosionRateCalc === null ? '—' : number_format($this->eclosionRateCalc, 1, ',', ' ').' %' }}</div>
                    </div>
                </div>
            </div>

            <div class="bg-error-bg/30 border border-error-red/20 rounded-lg p-sm">
                <p class="text-xs font-bold text-error-deep uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">skull</span>Morts par catégorie</p>
                @if($mortEnregistre !== null)
                    <p class="text-[11px] text-brand-forest bg-accent-yellow/20 border border-accent-yellow rounded-lg p-xs mb-xs" role="status">{{ $mortEnregistre }} mort(s) déjà enregistré(s) ce jour, sans répartition par catégorie : ventilez-les ci-dessous (Reproducteur / Jeune / Poussin) avant d'enregistrer.</p>
                @endif
                <div class="grid grid-cols-3 gap-sm">
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Reproducteur</label>
                        <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                            <button type="button" wire:click="$set('mortRepro', {{ max(0, $mortRepro - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                            <input wire:model.live="mortRepro" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                            <button type="button" wire:click="$set('mortRepro', {{ $mortRepro + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                        </div>
                    </div>
                    <div>
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Jeune</label>
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
                    <p class="text-[11px] text-brand-forest bg-accent-yellow/20 border border-accent-yellow rounded-lg p-xs mb-xs" role="status">{{ $donEnregistre }} don(s) déjà enregistré(s) ce jour, sans répartition par catégorie : ventilez-les ci-dessous (Reproducteur / Jeune / Poussin) avant d'enregistrer.</p>
                @endif
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
                        <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Jeune</label>
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

            {{-- Ticket VOL-1 — passage de stade du jour (Poussin → Jeune) : le seul mouvement qui fait passer les poussins nés dans
                 la catégorie Jeune ; sans lui les effectifs par catégorie dériveraient. Hors maquette, assumé. --}}
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Passage du jour (Poussin → Jeune)</label>
                    <input wire:model.live="passage" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
            </div>

            @if($cat['depart_requis'])
                {{-- Ticket VOL-1 : le DÉPART est exigé AVANT toute journée (aucune catégorie « inconnue » sur cette fiche). --}}
                <div id="depart-requis" class="bg-brand-emerald/5 border border-brand-emerald/20 rounded-lg p-sm">
                    <p class="text-xs font-bold text-brand-emerald uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">edit_note</span>Effectif de départ par catégorie (obligatoire)</p>
                    <p class="text-[10px] text-outline mb-xs">Cette bande n'a pas encore d'effectif de départ : saisissez l'effectif de chaque catégorie au DÉBUT de ce jour, avant les mouvements du jour. La somme des trois catégories doit égaler l'effectif total au début du jour ({{ $this->previousEffectif }}). Il est verrouillé au premier enregistrement ; la journée ne s'enregistre pas sans lui.</p>
                    <div class="grid grid-cols-3 gap-sm">
                        <div>
                            <label for="depart-repro" class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Reproducteur</label>
                            <input id="depart-repro" wire:model.live="departRepro" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border border-outline-variant rounded-lg bg-white">
                        </div>
                        <div>
                            <label for="depart-jeune" class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Jeune</label>
                            <input id="depart-jeune" wire:model.live="departJeune" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border border-outline-variant rounded-lg bg-white">
                        </div>
                        <div>
                            <label for="depart-sevre" class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Poussin</label>
                            <input id="depart-sevre" wire:model.live="departSevre" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border border-outline-variant rounded-lg bg-white">
                        </div>
                    </div>
                    @if($cat['proposition'])
                        <button type="button" wire:click="appliquerPropositionDepart" class="mt-sm text-[11px] font-bold text-brand-emerald underline">Reprendre la proposition d'après le stade de la bande (Reproducteur {{ $cat['proposition']['repro'] }} · Jeune {{ $cat['proposition']['jeune'] }} · Poussin {{ $cat['proposition']['sevre'] }})</button>
                    @endif
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
                            <label for="depart-jeune" class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Jeune</label>
                            <input id="depart-jeune" type="number" value="{{ $cat['depart']['jeune'] }}" disabled class="w-full h-9 text-center text-sm font-bold border border-outline-variant rounded-lg bg-surface-zebra text-outline cursor-not-allowed">
                        </div>
                        <div>
                            <label for="depart-sevre" class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">Poussin</label>
                            <input id="depart-sevre" type="number" value="{{ $cat['depart']['sevre'] }}" disabled class="w-full h-9 text-center text-sm font-bold border border-outline-variant rounded-lg bg-surface-zebra text-outline cursor-not-allowed">
                        </div>
                    </div>
                    @if($cat['mode'] === 'avant_depart')
                        <p id="avant-depart" class="text-[10px] text-error-deep font-bold mt-xs">Jour antérieur à l'effectif de départ fixé le {{ \Carbon\Carbon::parse($cat['depart_date'])->format('d/m/Y') }} : il n'est pas saisissable.</p>
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
            @if($ventesJ['non_ventilee'])
                <div class="bg-accent-yellow/20 border border-accent-yellow rounded-lg p-sm text-xs text-brand-forest" role="status">Cette journée porte des ventes d'avant la mise en place des catégories, non ventilées : elle ne peut pas être ré-enregistrée.</div>
            @endif

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

            {{-- Ticket VOL-1 — rationnement PAR CATÉGORIE : effectif calculé × ration de la ligne du barème (Reproducteur, Jeune,
                 Poussin). Tant que le départ n'est pas valide, la demande de départ ci-dessus tient lieu d'effectif. --}}
            @php $ration = $this->rationnement; @endphp
            <div>
                <p class="text-xs font-bold text-brand-forest uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px] text-brand-emerald">restaurant</span>Rationnement &amp; Provende Servie par Catégorie (en Grammes g/j)</p>
                @if($cat['repro'] === null)
                    <p id="ration-depart-requis" class="text-xs text-outline bg-surface-zebra border border-outline-variant rounded-lg p-md">Saisissez l'effectif de départ de la bande pour calculer les effectifs par catégorie et la provende servie.</p>
                @else
                    <div class="bg-white border border-outline-variant rounded-lg overflow-hidden shadow-sm">
                        <table class="w-full text-xs">
                            <thead class="bg-surface-zebra text-outline border-b border-outline-variant">
                                <tr><th class="px-md py-xs text-left">Catégorie</th><th class="px-md py-xs text-center">Effectif</th><th class="px-md py-xs text-center">Ration Normative</th><th class="px-md py-xs text-right">Provende Servie (g)</th></tr>
                            </thead>
                            <tbody class="divide-y divide-outline-variant/60">
                                @foreach($ration['lignes'] as $ligne)
                                    <tr wire:key="ration-{{ $ligne['cle'] }}">
                                        <td class="px-md py-xs font-bold text-brand-forest">{{ $ligne['libelle'] }}</td>
                                        {{-- Effectifs CALCULÉS (jamais saisis) : disabled, donc non focalisables. --}}
                                        <td class="px-md py-xs text-center"><input id="cat-eff-{{ $ligne['cle'] }}" type="text" inputmode="numeric" disabled value="{{ $ligne['effectif'] }}" title="Calculé automatiquement depuis le départ, les achats, éclosions, ventes, morts, dons et le passage du jour." class="w-16 h-8 text-center border border-outline-variant rounded text-xs font-bold bg-surface-zebra"></td>
                                        <td class="px-md py-xs text-center font-mono">{{ $ligne['ration'] }} g/j</td>
                                        <td id="cat-prov-{{ $ligne['cle'] }}-g" class="px-md py-xs text-right font-mono font-bold text-brand-emerald">{{ $ligne['total_g'] }} g</td>
                                    </tr>
                                @endforeach
                            </tbody>
                            <tfoot class="bg-brand-emerald/10 font-bold text-brand-forest border-t border-brand-emerald/20">
                                <tr><td colspan="3" class="px-md py-xs uppercase text-[10px]">TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)</td><td id="day-total-provende-g" class="px-md py-xs text-right font-mono text-sm text-brand-emerald">{{ $ration['total_g'] }} g ({{ $ration['total_kg'] }} Kg)</td></tr>
                            </tfoot>
                        </table>
                    </div>
                @endif
            </div>

            <x-autonomie-alimentaire :autonomie="$this->feedAutonomy" filiere="aviculture" />

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Poids Général Pesé (g)</label>
                    <input wire:model.live="peseeTotal" type="number" min="0"
                        placeholder="{{ $this->poidsMoyenEstime !== null && $this->effectifFinalCalc > 0 ? '~'.($this->poidsMoyenEstime * $this->effectifFinalCalc).' g (estimé)' : 'ex : 1800' }}"
                        class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Poids Moyen Constaté <span class="text-outline normal-case font-normal">(Poids Général ÷ Effectif Final)</span></label>
                    <div class="h-10 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center font-bold text-brand-emerald">
                        {{ $peseeTotal && $this->effectifFinalCalc > 0 ? round($peseeTotal / $this->effectifFinalCalc).' g' : '—' }}
                    </div>
                </div>
            </div>
            @if($this->poidsMoyenEstime !== null)
                <p class="text-xs text-outline italic flex items-center gap-xs mt-xs">
                    <span class="material-symbols-outlined text-[14px]">trending_up</span>
                    Poids moyen estimé (GMQ) : <span class="font-bold text-brand-forest not-italic">{{ $this->poidsMoyenEstime }} g / animal</span>
                </p>
            @endif

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
            </fieldset>
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
                        <th class="px-sm py-xs text-center text-[9px] text-outline font-bold border-r border-outline-variant">Reproducteur+Jeune+Poussin</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach($this->daysInMonth as $day)
                        @php
                            $dateStr = $this->debutMoisFiche()->addDays($day - 1)->format('Y-m-d');   // EX8 : le mois affiché
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
        <p class="text-[10px] text-outline p-sm border-t border-outline-variant">La ventilation Reproducteur / Jeune / Poussin des morts, des dons et des ventes est conservée par catégorie (ticket VOL-1) — le tableau mensuel en affiche le cumul.</p>
    </div>
    @endif
</div>
