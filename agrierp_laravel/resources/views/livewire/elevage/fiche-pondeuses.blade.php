<div>
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">egg</span>Fiches Pondeuses - Aviculture
            </h2>
            <p class="text-xs text-outline mt-xs">Suivi quotidien de la ponte et récolte d'œufs — transcription fidèle du registre de la ferme.</p>
        </div>
        <button type="button" wire:click="exportFichePdf" wire:loading.attr="disabled" wire:target="exportFichePdf" class="flex items-center gap-xs bg-white border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>{{ __('elevage.bouton_exporter_pdf') }}
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
            <a wire:navigate href="{{ route('elevage.bandes') }}" class="text-xs font-bold text-brand-emerald mt-sm inline-block">Créer une bande depuis Bandes &amp; Sujets →</a>
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

        @php
            $cat = $this->categoriesJour; $ventesJ = $this->ventesDuJour;
            // Ticket VOL-2 — les QUATRE stades, dans l'ordre de la chaîne, aux libellés EXACTS du barème de l'aviculture.
            $stades = [
                ['cle' => 'poussin_ponte', 'emp' => 'quatre', 'mort' => 'mortPoussinPonte', 'don' => 'donPoussinPonte', 'depart' => 'departPoussinPonte'],
                ['cle' => 'poussin_croissance', 'emp' => 'sevre', 'mort' => 'mortPoussinCroissance', 'don' => 'donPoussinCroissance', 'depart' => 'departPoussinCroissance'],
                ['cle' => 'poulette', 'emp' => 'jeune', 'mort' => 'mortPoulette', 'don' => 'donPoulette', 'depart' => 'departPoulette'],
                ['cle' => 'pondeuse', 'emp' => 'repro', 'mort' => 'mortPondeuse', 'don' => 'donPondeuse', 'depart' => 'departPondeuse'],
            ];
            $libellesStades = \App\Support\StadePondeuse::LIBELLES;
        @endphp

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
                    {{-- Ticket VOL-2 : la caisse range chaque vente dans le stade du PRODUIT vendu (lecture seule). --}}
                    <p id="ventes-par-stade" class="text-[10px] text-outline mt-xs">@foreach($stades as $st){{ $libellesStades[$st['cle']] }} {{ $ventesJ[$st['emp']] }}{{ $loop->last ? '' : ' · ' }}@endforeach</p>
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
                    <p class="text-[11px] text-brand-forest bg-accent-yellow/20 border border-accent-yellow rounded-lg p-xs mb-xs" role="status">{{ $mortEnregistre }} mort(s) déjà enregistré(s) ce jour, sans répartition par catégorie : ventilez-les ci-dessous (Poussin ponte / Poussin en croissance / Poulette / Pondeuse) avant d'enregistrer.</p>
                @endif
                <div class="grid grid-cols-2 sm:grid-cols-4 gap-sm">
                    @foreach($stades as $st)
                        <div wire:key="mort-{{ $st['cle'] }}">
                            <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">{{ $libellesStades[$st['cle']] }}</label>
                            <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                                <button type="button" wire:click="$set('{{ $st['mort'] }}', {{ max(0, $this->{$st['mort']} - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                                <input wire:model.live="{{ $st['mort'] }}" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                                <button type="button" wire:click="$set('{{ $st['mort'] }}', {{ $this->{$st['mort']} + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                            </div>
                        </div>
                    @endforeach
                </div>
            </div>

            {{-- Ticket 15.56 — dons par stade : un don réduit l'effectif et sort du stock du produit de la bande. --}}
            <div class="bg-brand-emerald/5 border border-brand-emerald/20 rounded-lg p-sm">
                <p class="text-xs font-bold text-brand-emerald uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">redeem</span>Dons par catégorie</p>
                @if($donEnregistre !== null)
                    <p class="text-[11px] text-brand-forest bg-accent-yellow/20 border border-accent-yellow rounded-lg p-xs mb-xs" role="status">{{ $donEnregistre }} don(s) déjà enregistré(s) ce jour, sans répartition par catégorie : ventilez-les ci-dessous (Poussin ponte / Poussin en croissance / Poulette / Pondeuse) avant d'enregistrer.</p>
                @endif
                <div class="grid grid-cols-2 sm:grid-cols-4 gap-sm">
                    @foreach($stades as $st)
                        <div wire:key="don-{{ $st['cle'] }}">
                            <label class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">{{ $libellesStades[$st['cle']] }}</label>
                            <div class="flex items-center border border-outline-variant rounded-lg bg-white overflow-hidden">
                                <button type="button" wire:click="$set('{{ $st['don'] }}', {{ max(0, $this->{$st['don']} - 1) }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">−</button>
                                <input wire:model.live="{{ $st['don'] }}" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border-0">
                                <button type="button" wire:click="$set('{{ $st['don'] }}', {{ $this->{$st['don']} + 1 }})" class="w-8 h-9 bg-surface-zebra text-brand-forest font-bold">+</button>
                            </div>
                        </div>
                    @endforeach
                </div>
            </div>

            {{-- Ticket VOL-2 — les TROIS passages de stade du jour (Poussin ponte → Poussin en croissance → Poulette → Pondeuse) :
                 les seuls mouvements qui font avancer les sujets d'un stade à l'autre ; sans eux les effectifs par stade dériveraient. --}}
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Passage du jour (Poussin ponte → Poussin en croissance)</label>
                    <input id="passage-1" wire:model.live="passage1" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Passage du jour (Poussin en croissance → Poulette)</label>
                    <input id="passage-2" wire:model.live="passage2" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Passage du jour (Poulette → Pondeuse)</label>
                    <input id="passage-3" wire:model.live="passage3" type="number" min="0" class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
            </div>

            @if($cat['depart_requis'])
                {{-- Ticket VOL-2 : le DÉPART est exigé AVANT toute journée (aucun stade « inconnu » sur cette fiche). --}}
                <div id="depart-requis" class="bg-brand-emerald/5 border border-brand-emerald/20 rounded-lg p-sm">
                    <p class="text-xs font-bold text-brand-emerald uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">edit_note</span>Effectif de départ par stade (obligatoire)</p>
                    <p class="text-[10px] text-outline mb-xs">Cette bande n'a pas encore d'effectif de départ : saisissez l'effectif de chaque stade au DÉBUT de ce jour, avant les mouvements du jour. La somme des quatre stades doit égaler l'effectif total au début du jour ({{ $this->previousEffectif }}). Il est verrouillé au premier enregistrement ; la journée ne s'enregistre pas sans lui.</p>
                    <div class="grid grid-cols-2 sm:grid-cols-4 gap-sm">
                        @foreach($stades as $st)
                            <div wire:key="depart-{{ $st['cle'] }}">
                                <label for="depart-{{ $st['emp'] }}" class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">{{ $libellesStades[$st['cle']] }}</label>
                                <input id="depart-{{ $st['emp'] }}" wire:model.live="{{ $st['depart'] }}" type="number" min="0" class="w-full h-9 text-center text-sm font-bold border border-outline-variant rounded-lg bg-white">
                            </div>
                        @endforeach
                    </div>
                    @if($cat['proposition'])
                        <button type="button" wire:click="appliquerPropositionDepart" class="mt-sm text-[11px] font-bold text-brand-emerald underline">Reprendre la proposition d'après le stade de la bande ({{ $libellesStades['pondeuse'] }} {{ $cat['proposition']['repro'] }} · {{ $libellesStades['poulette'] }} {{ $cat['proposition']['jeune'] }} · {{ $libellesStades['poussin_croissance'] }} {{ $cat['proposition']['sevre'] }} · {{ $libellesStades['poussin_ponte'] }} {{ $cat['proposition']['quatre'] }})</button>
                    @endif
                </div>
            @elseif($cat['depart'])
                <div class="bg-surface-zebra border border-outline-variant rounded-lg p-sm">
                    <p class="text-xs font-bold text-brand-forest uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">lock</span>Effectif de départ par stade (verrouillé)</p>
                    <p class="text-[10px] text-outline mb-xs">Effectif de départ fixé le {{ \Carbon\Carbon::parse($cat['depart_date'])->format('d/m/Y') }} (au début de ce jour).</p>
                    <div class="grid grid-cols-2 sm:grid-cols-4 gap-sm">
                        @foreach($stades as $st)
                            <div wire:key="depart-verrou-{{ $st['cle'] }}">
                                <label for="depart-{{ $st['emp'] }}" class="block text-[9px] text-outline font-bold uppercase mb-xs text-center">{{ $libellesStades[$st['cle']] }}</label>
                                <input id="depart-{{ $st['emp'] }}" type="number" value="{{ $cat['depart'][$st['emp']] }}" disabled class="w-full h-9 text-center text-sm font-bold border border-outline-variant rounded-lg bg-surface-zebra text-outline cursor-not-allowed">
                            </div>
                        @endforeach
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
                <div class="bg-accent-yellow/20 border border-accent-yellow rounded-lg p-sm text-xs text-brand-forest" role="status">Cette journée porte des ventes d'avant la mise en place des stades, non ventilées : elle ne peut pas être ré-enregistrée.</div>
            @endif

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

            {{-- Ticket VOL-2 — rationnement PAR STADE : effectif calculé de chaque stade × la ration de sa ligne du barème (les
                 quatre libellés du barème). Tant que le départ n'est pas valide, la demande de départ tient lieu d'effectif. --}}
            @php $ration = $this->rationnement; @endphp
            <div>
                <p class="text-xs font-bold text-brand-forest uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px] text-brand-emerald">restaurant</span>Rationnement &amp; Provende Servie par Stade (en Grammes g/j)</p>
                @if($cat['repro'] === null)
                    <p id="ration-depart-requis" class="text-xs text-outline bg-surface-zebra border border-outline-variant rounded-lg p-md">Saisissez l'effectif de départ de la bande pour calculer les effectifs par stade et la provende servie.</p>
                @else
                    <div class="bg-white border border-outline-variant rounded-lg overflow-hidden shadow-sm">
                        <table class="w-full text-xs">
                            <thead class="bg-surface-zebra text-outline border-b border-outline-variant">
                                <tr><th class="px-md py-xs text-left">Stade / Tranche d'Âge</th><th class="px-md py-xs text-center">Effectif</th><th class="px-md py-xs text-center">Ration Normative</th><th class="px-md py-xs text-right">Provende Servie (g)</th></tr>
                            </thead>
                            <tbody class="divide-y divide-outline-variant/60">
                                @foreach($ration['lignes'] as $ligne)
                                    <tr wire:key="ration-{{ $ligne['cle'] }}">
                                        <td class="px-md py-xs font-bold text-brand-forest">{{ $ligne['libelle'] }}</td>
                                        {{-- Effectifs CALCULÉS (jamais saisis) : disabled, donc non focalisables. --}}
                                        <td class="px-md py-xs text-center"><input id="cat-eff-{{ $ligne['cle'] }}" type="text" inputmode="numeric" disabled value="{{ $ligne['effectif'] }}" title="Calculé automatiquement depuis le départ, les achats, éclosions, ventes, morts, dons et les passages du jour." class="w-16 h-8 text-center border border-outline-variant rounded text-xs font-bold bg-surface-zebra"></td>
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
