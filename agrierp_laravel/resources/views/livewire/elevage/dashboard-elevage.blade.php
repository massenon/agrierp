<div>
    <x-tab-page
        :tabs="[
            ['key' => 'synthese', 'label' => 'Synthèse Globale', 'icon' => 'dashboard'],
            ['key' => 'gmq', 'label' => 'GMQ & Croissance', 'icon' => 'monitoring'],
            {{-- Libellé « Rentabilité » : décision client du 17/10/2026 (le prototype dit « Bilan Technico-Économique »). --}}
            ['key' => 'bilan', 'label' => 'Rentabilité', 'icon' => 'account_balance_wallet'],
            ['key' => 'sanitaire', 'label' => 'Analyse Sanitaire', 'icon' => 'coronavirus'],
            ['key' => 'prevision', 'label' => 'Prévision de Croissance', 'icon' => 'query_stats'],
        ]"
        :active="$tab">

        @if($tab === 'synthese')
            <div class="mt-md space-y-md">
                <x-kpi-accordion title="Indicateurs de performance">
                    <x-kpi-card label="Effectif Total Vivant" icon="pets" color="emerald" :value="number_format($this->syntheseKpis['effectif_total'], 0, ',', ' ')" caption="Toutes espèces actives" />
                    <x-kpi-card label="Autonomie Aliment Min." icon="inventory_2" color="maize" :pending="true" pending-since="Sprint 6 (Stocks) — suivi de stock d'aliment réel" />
                    <x-kpi-card label="GMQ Moyen" icon="trending_up" color="blue"
                        :value="$this->syntheseKpis['gmq_moyen'] !== null ? $this->syntheseKpis['gmq_moyen'].' g/j' : '—'"
                        :caption="$this->syntheseKpis['gmq_moyen'] === null ? 'Moins de 2 pesées enregistrées' : 'Consolidé, toutes bandes'" />
                    <x-kpi-card label="Mortalité Cumulée (7j)" icon="health_and_safety" color="red" :value="number_format($this->syntheseKpis['taux_mortalite_7j'], 1, ',', ' ').' %'" caption="Alerte si > 10%/semaine" />
                </x-kpi-accordion>

                <div class="grid grid-cols-1 lg:grid-cols-4 gap-md">
                    @foreach($this->speciesSummary as $row)
                        <div class="bg-white border border-outline-variant rounded-lg p-md">
                            <div class="flex items-center gap-xs mb-sm">
                                <span class="material-symbols-outlined text-brand-emerald text-[20px]">{{ $row['species']->icon ?? 'pets' }}</span>
                                <h3 class="text-sm font-bold text-brand-forest">{{ $row['species']->label }}</h3>
                            </div>
                            <div class="space-y-1 text-xs">
                                <div class="flex justify-between"><span class="text-outline">Effectif vivant</span><span class="font-bold">{{ $row['effectif'] }}</span></div>
                                <div class="flex justify-between"><span class="text-outline">Taux mortalité (mois)</span><span class="font-bold {{ $row['taux_mortalite'] > 5 ? 'text-error-deep' : '' }}">{{ number_format($row['taux_mortalite'], 1, ',', ' ') }} %</span></div>
                                <div class="flex justify-between"><span class="text-outline">Autonomie aliment</span><span class="font-bold text-outline">—</span></div>
                                {{-- Ticket H11 — ligne propre à la filière (ajout du poste, décision client du 19/10/2026). --}}
                                @if($row['ligne_poste'])
                                    @include('livewire.elevage.ajouts-poste.dashboard-ligne-filiere', ['ligne' => $row['ligne_poste']])
                                @endif
                            </div>
                        </div>
                    @endforeach
                </div>

                <div class="grid grid-cols-1 lg:grid-cols-[65%_35%] gap-md">
                    <div class="bg-white border border-outline-variant rounded-lg p-md">
                        <h3 class="text-sm font-bold text-brand-forest mb-md">GMQ par Bande — Résumé</h3>
                        <p class="text-[10px] text-outline mb-sm">Le graphique de croissance du prototype est remplacé par un tableau réel (aucune librairie de graphiques disponible côté vue à ce stade) — voir l'onglet « GMQ &amp; Croissance » pour le détail complet.</p>
                        @if($this->gmqTable->where('gmq', '!=', null)->isEmpty())
                            <p class="text-xs text-outline text-center py-lg">Aucune donnée de croissance suffisante pour le moment (2 pesées minimum par bande).</p>
                        @else
                            <div class="space-y-xs">
                                @foreach($this->gmqTable->whereNotNull('gmq') as $row)
                                    <div class="flex justify-between text-xs border-b border-outline-variant/50 py-1">
                                        <span class="font-bold text-brand-forest">{{ $row['lot']->code }}</span>
                                        <span class="font-mono {{ $row['gmq'] < 0 ? 'text-error-deep' : 'text-brand-emerald' }} font-bold">{{ $row['gmq'] }} g/j</span>
                                    </div>
                                @endforeach
                            </div>
                        @endif
                    </div>
                    <div class="bg-white border border-outline-variant rounded-lg p-md">
                        <h3 class="text-sm font-bold text-brand-forest mb-md">Rappels VMS à venir</h3>
                        {{-- Ticket H11 — liste calculée des rappels des 7 prochains jours (ajout du poste), au-dessus du texte et du lien. --}}
                        @include('livewire.elevage.ajouts-poste.dashboard-rappels-vms', ['rappels' => $this->rappelsVms])
                        <p class="text-xs text-outline text-center py-md">Le calendrier complet (réel) est disponible dans Soins et Vaccins.</p>
                        <a href="{{ route('elevage.soins-vaccins') }}" class="block text-center mt-md text-xs font-bold text-brand-emerald hover:underline">Voir le calendrier complet →</a>
                    </div>
                </div>

                {{-- Ticket H11 — courbe hebdomadaire du GMQ cumulé par espèce (ajout du poste). --}}
                @include('livewire.elevage.ajouts-poste.dashboard-courbe-especes', ['series' => $this->gmqParEspeceParSemaine])
            </div>
        @endif

        @if($tab === 'gmq')
            <div class="mt-md space-y-md">
                <div class="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-sm">
                    <div>
                        <h2 class="text-lg font-bold flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald">monitoring</span>GMQ &amp; Croissance</h2>
                        <p class="text-xs text-outline mt-xs">GMQ (g/j) = (Poids Final − Poids Initial) ÷ Nombre de Jours entre les deux pesées, calculé par bande à partir des pesées déjà saisies dans les fiches journalières.</p>
                    </div>
                    {{-- Ticket H11 — filtre d'espèce du poste. --}}
                    @include('livewire.elevage.ajouts-poste.dashboard-filtre-espece')
                </div>

                {{-- Ticket H11 — cartes et courbe du poste, sur le MÊME GMQ cumulé que le tableau. --}}
                @include('livewire.elevage.ajouts-poste.dashboard-gmq', ['cartes' => $this->gmqCartes, 'suivie' => $this->bandeSuivie, 'evolution' => $this->evolutionGmq])
                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="overflow-x-auto">
                        <table class="w-full rtable text-xs">
                            <thead class="bg-surface-zebra border-b border-outline-variant">
                                <tr>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Bande</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Filière</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Poids Initial (g)</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Poids Actuel (g)</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Jours</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">GMQ (g/jour)</th>
                                </tr>
                            </thead>
                            <tbody>
                                @forelse($this->gmqTableFiltree as $i => $row)
                                    <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                        <td data-label="Bande" class="px-md py-sm font-bold text-brand-forest">{{ $row['lot']->code }}</td>
                                        <td data-label="Filière" class="px-md py-sm">{{ $row['lot']->species?->label }}</td>
                                        <td data-label="Poids Initial" class="px-md py-sm text-right">{{ $row['poids_initial'] ?? '—' }}</td>
                                        <td data-label="Poids Actuel" class="px-md py-sm text-right">{{ $row['poids_actuel'] ?? '—' }}</td>
                                        <td data-label="Jours" class="px-md py-sm text-right">{{ $row['jours'] ?? '—' }}</td>
                                        <td data-label="GMQ" class="px-md py-sm text-right font-bold {{ $row['gmq'] !== null && $row['gmq'] < 0 ? 'text-error-deep' : 'text-brand-emerald' }}">{{ $row['gmq'] !== null ? $row['gmq'].' g/j' : 'Pesées insuffisantes' }}</td>
                                    </tr>
                                @empty
                                    <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucune bande active pour le moment.</td></tr>
                                @endforelse
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        @endif

        @if($tab === 'bilan')
            <div class="mt-md">
                <livewire:elevage.bilan-technico-economique />
            </div>
        @endif

        @if($tab === 'sanitaire')
            <div class="mt-md space-y-md">
                <div>
                    <h2 class="text-lg font-bold flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald">coronavirus</span>Analyse Sanitaire — Fréquence des Maladies</h2>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-3 gap-md">
                    <x-kpi-card label="Traitements Administrés (mois)" icon="vaccines" color="emerald" :value="$this->sanitaireKpis['nb_traitements_mois']" />
                    <x-kpi-card label="Coût Sanitaire Total (mois)" icon="payments" color="red" :value="number_format($this->sanitaireKpis['cout_sanitaire_mois'], 0, ',', ' ').' FCFA'" />
                    <x-kpi-card label="Traitement le Plus Fréquent" icon="star" color="blue" :value="$this->sanitaireKpis['traitement_frequent'] ?? '—'" />
                </div>
                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="overflow-x-auto">
                        <table class="w-full rtable text-xs">
                            <thead class="bg-surface-zebra border-b border-outline-variant">
                                <tr>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Filière</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Nb Traitements (mois)</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Coût Total</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Taux de Morbidité %</th>
                                </tr>
                            </thead>
                            <tbody>
                                @foreach($this->sanitaireBySpecies as $i => $row)
                                    <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                        <td data-label="Filière" class="px-md py-sm font-bold text-brand-forest">{{ $row['species']->label }}</td>
                                        <td data-label="Traitements" class="px-md py-sm text-right">{{ $row['nb_traitements'] }}</td>
                                        <td data-label="Coût" class="px-md py-sm text-right">{{ number_format($row['cout_total'], 0, ',', ' ') }} FCFA</td>
                                        <td data-label="Morbidité" class="px-md py-sm text-right {{ $row['taux_morbidite'] > 5 ? 'text-error-deep font-bold' : '' }}">{{ number_format($row['taux_morbidite'], 1, ',', ' ') }} %</td>
                                    </tr>
                                @endforeach
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        @endif

        @if($tab === 'prevision')
            <div class="mt-md space-y-md">
                <div>
                    <h2 class="text-lg font-bold flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald">query_stats</span>Prévision de Croissance</h2>
                    <p class="text-xs text-outline mt-xs">Régression linéaire simple sur l'historique des pesées (minimum 3 points requis).</p>
                </div>
                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="overflow-x-auto">
                        <table class="w-full rtable text-xs">
                            <thead class="bg-surface-zebra border-b border-outline-variant">
                                <tr>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Bande</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Poids Actuel (g)</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Tendance (g/j)</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Projection à 30 jours (g)</th>
                                </tr>
                            </thead>
                            <tbody>
                                @forelse($this->previsions as $i => $row)
                                    <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                        <td data-label="Bande" class="px-md py-sm font-bold text-brand-forest">{{ $row['lot']->code }}</td>
                                        @if($row['insufficient'])
                                            <td colspan="3" class="px-md py-sm text-center text-outline italic">Historique insuffisant (3 pesées minimum requises)</td>
                                        @else
                                            <td data-label="Poids Actuel" class="px-md py-sm text-right">{{ $row['poids_actuel'] }}</td>
                                            <td data-label="Tendance" class="px-md py-sm text-right {{ $row['tendance_g_par_jour'] < 0 ? 'text-error-deep' : 'text-brand-emerald' }} font-bold">{{ $row['tendance_g_par_jour'] }} g/j</td>
                                            <td data-label="Projection 30j" class="px-md py-sm text-right font-bold">{{ $row['projection_30j'] }}</td>
                                        @endif
                                    </tr>
                                @empty
                                    <tr><td colspan="4" class="px-md py-lg text-center text-outline">Aucune bande active pour le moment.</td></tr>
                                @endforelse
                            </tbody>
                        </table>
                    </div>
                </div>

                {{-- Ticket H11 — ajouts du poste : sélecteur de bande, horizons, trois cartes et projection par horizon. --}}
                @include('livewire.elevage.ajouts-poste.dashboard-prevision', ['choisie' => $this->previsionChoisie, 'projetables' => $this->previsionsProjetables, 'horizon' => $horizon])
            </div>
        @endif
    </x-tab-page>
</div>
