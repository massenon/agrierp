<div>
    {{-- Ticket 15.51 — assistant de démarrage (administrateur, tant qu'il n'est pas marqué terminé). --}}
    <livewire:parametres.assistant-demarrage />

    <div class="flex flex-col gap-md border-b border-outline-variant pb-md mb-lg">
        <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm">
            <div>
                <h2 class="text-xl lg:text-2xl font-bold text-on-surface">Bienvenue, {{ auth()->user()->name }} 👋</h2>
                <p class="text-xs text-outline mt-xs">Rapport généré le {{ now()->translatedFormat('d/m/Y à H:i') }} · {{ $this->details['exercice'] ? 'Exercice '.$this->details['exercice'].($this->details['exercice_clos'] ? ' clôturé' : ' actif') : 'Aucun exercice ouvert' }}</p>
            </div>
            <div class="flex flex-wrap items-center gap-xs">
                <a wire:navigate href="/ventes-devis" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
                    <span class="material-symbols-outlined text-[18px]">point_of_sale</span>Enregistrer une Vente
                </a>
                <a wire:navigate href="/gestion-elevage" class="flex items-center justify-center gap-xs bg-white border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
                    <span class="material-symbols-outlined text-[18px]">pets</span>Élevage
                </a>
            </div>
        </div>

        <div class="flex flex-col sm:flex-row items-stretch sm:items-center gap-sm bg-white border border-outline-variant rounded-lg p-sm">
            <div class="flex items-center gap-xs flex-1">
                <span class="material-symbols-outlined text-outline text-[18px]">calendar_month</span>
                <input type="date" value="{{ now()->startOfMonth()->format('Y-m-d') }}" class="text-xs border border-outline-variant rounded-lg px-sm py-1.5 flex-1" disabled>
                <span class="text-outline text-xs">au</span>
                <input type="date" value="{{ now()->format('Y-m-d') }}" class="text-xs border border-outline-variant rounded-lg px-sm py-1.5 flex-1" disabled>
            </div>
            <div class="flex items-center gap-xs" x-data="{ report: '' }">
                <select x-model="report" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white flex-1 sm:w-56">
                    <option value="">-- Choisir un état / rapport --</option>
                    <option value="/rapports-exports?tab=recettes-depenses">État des Recettes</option>
                    <option value="/rapports-exports?tab=recettes-depenses">État des Dépenses</option>
                    <option value="/rapports-exports?tab=tresorerie">État de Trésorerie</option>
                    <option value="/rapport-bilan">Bilan Simplifié</option>
                    <option value="/rapports-exports?tab=creances">État des Créances</option>
                    <option value="/rapports-exports?tab=dettes">État des Dettes</option>
                    <option value="/rapports-exports?tab=elevage-synth">Rapport Élevage</option>
                    <option value="/rapports-exports?tab=stocks-synth">Rapport de Stocks</option>
                </select>
                <button type="button" x-on:click="if (report) window.location.href = report" :disabled="!report" class="flex items-center gap-1 text-xs font-bold px-md py-2 rounded-lg bg-brand-emerald text-white hover:bg-brand-forest disabled:bg-surface-zebra disabled:text-outline disabled:cursor-not-allowed"><span class="material-symbols-outlined text-[16px]">picture_as_pdf</span>PDF</button>
            </div>
        </div>
    </div>

    @php
        $pctChange = function (?float $current, ?float $previous): ?string {
            if ($previous === null || $previous == 0.0 || $current === null) {
                return null;
            }
            $pct = (($current - $previous) / abs($previous)) * 100;

            return ($pct >= 0 ? '+' : '').number_format($pct, 1, ',', ' ').'%';
        };
    @endphp
    <x-kpi-accordion title="Indicateurs de performance">
        <x-kpi-card label="Chiffre d'Affaires" icon="trending_up" color="emerald" unit="FCFA"
            :pending="$this->kpis['ca']['pending']" :pending-since="$this->kpis['ca']['since'] ?? null"
            :value="isset($this->kpis['ca']['value']) ? number_format($this->kpis['ca']['value'], 0, ',', ' ') : null"
            :caption="isset($this->kpis['ca']['previous']) ? 'Mois précédent : '.number_format($this->kpis['ca']['previous'], 0, ',', ' ').' F'.($pctChange($this->kpis['ca']['value'], $this->kpis['ca']['previous']) ? ' ('.$pctChange($this->kpis['ca']['value'], $this->kpis['ca']['previous']).')' : '') : null" />
        <x-kpi-card label="Trésorerie" icon="account_balance_wallet" color="blue" unit="FCFA"
            :pending="$this->kpis['tresorerie']['pending']" :pending-since="$this->kpis['tresorerie']['since'] ?? null"
            :value="isset($this->kpis['tresorerie']['value']) ? number_format($this->kpis['tresorerie']['value'], 0, ',', ' ') : null"
            :caption="isset($this->kpis['tresorerie']['value']) ? 'Caisse : '.number_format($this->details['caisse'], 0, ',', ' ').' F · Banque : '.number_format($this->details['banque'], 0, ',', ' ').' F · Mobile Money : '.number_format($this->details['mobile_money'], 0, ',', ' ').' F' : null" />
        <x-kpi-card label="Dépenses" icon="shopping_cart" color="maize" unit="FCFA"
            :pending="$this->kpis['depenses']['pending']" :pending-since="$this->kpis['depenses']['since'] ?? null"
            :value="isset($this->kpis['depenses']['value']) ? number_format($this->kpis['depenses']['value'], 0, ',', ' ') : null"
            :caption="isset($this->kpis['depenses']['previous']) ? 'Mois précédent : '.number_format($this->kpis['depenses']['previous'], 0, ',', ' ').' F'.($pctChange($this->kpis['depenses']['value'], $this->kpis['depenses']['previous']) ? ' ('.$pctChange($this->kpis['depenses']['value'], $this->kpis['depenses']['previous']).')' : '') : null" />
        <x-kpi-card label="Résultat Net" icon="savings" color="emerald" unit="FCFA"
            :pending="$this->kpis['resultat_net']['pending']" :pending-since="$this->kpis['resultat_net']['since'] ?? null"
            :value="isset($this->kpis['resultat_net']['value']) ? number_format($this->kpis['resultat_net']['value'], 0, ',', ' ') : null"
            :caption="isset($this->kpis['resultat_net']['value'], $this->kpis['ca']['value']) && $this->kpis['ca']['value'] > 0 ? 'Marge nette : '.number_format(($this->kpis['resultat_net']['value'] / $this->kpis['ca']['value']) * 100, 0, ',', ' ').'%' : null" />
        <x-kpi-card label="Créances Clients" icon="request_quote" color="red" unit="FCFA"
            :pending="$this->kpis['creances']['pending']" :pending-since="$this->kpis['creances']['since'] ?? null"
            :value="isset($this->kpis['creances']['value']) ? number_format($this->kpis['creances']['value'], 0, ',', ' ') : null" />
        <x-kpi-card label="Dettes Fournisseurs" icon="local_shipping" color="maize" unit="FCFA"
            :pending="$this->kpis['dettes']['pending']" :pending-since="$this->kpis['dettes']['since'] ?? null"
            :value="isset($this->kpis['dettes']['value']) ? number_format($this->kpis['dettes']['value'], 0, ',', ' ') : null" />
        <x-kpi-card label="Stock Critique" icon="warning" color="red" unit="produits"
            :pending="$this->kpis['stock_critique']['pending']" :pending-since="$this->kpis['stock_critique']['since'] ?? null"
            :value="$this->kpis['stock_critique']['value'] ?? null"
            :caption="isset($this->kpis['stock_critique']['value']) ? ($this->details['produits_critiques'] === [] ? 'Aucun produit sous son seuil' : implode(', ', $this->details['produits_critiques'])) : null" />
        <x-kpi-card label="Effectif Animaux" icon="pets" color="emerald" unit="têtes"
            :pending="$this->kpis['effectif_animaux']['pending']" :pending-since="$this->kpis['effectif_animaux']['since'] ?? null"
            :value="isset($this->kpis['effectif_animaux']['value']) ? number_format($this->kpis['effectif_animaux']['value'], 0, ',', ' ') : null" />
    </x-kpi-accordion>

    <div class="grid grid-cols-1 lg:grid-cols-12 gap-md mb-lg">
        <div class="lg:col-span-8 bg-white rounded-lg border border-outline-variant shadow-sm p-md">
            <h3 class="text-sm font-bold text-on-surface mb-md">CA vs Dépenses — 6 derniers mois</h3>
            @if($this->chartVentesDepenses === null)
                <x-module-pending label="Ce graphique" since="Sprints 4-5 (Ventes & Achats)" />
            @else
                @php
                    $chart = $this->chartVentesDepenses;
                    $allValues = array_merge($chart['ca'], $chart['depenses']);
                    $maxVal = max(1, max($allValues));
                    $xs = [70, 160, 250, 340, 430, 520];
                    $toY = fn ($v) => 190 - (($v / $maxVal) * 170);
                    $caPoints = collect($chart['ca'])->map(fn ($v, $i) => $xs[$i].','.round($toY($v), 1))->implode(' ');
                    $depPoints = collect($chart['depenses'])->map(fn ($v, $i) => $xs[$i].','.round($toY($v), 1))->implode(' ');
                @endphp
                <svg viewBox="0 0 600 220" class="w-full h-52">
                    <line x1="40" y1="10" x2="40" y2="190" stroke="#bec9c2" stroke-width="1"/>
                    <line x1="40" y1="190" x2="580" y2="190" stroke="#bec9c2" stroke-width="1"/>
                    <polyline fill="none" stroke="#065f46" stroke-width="3" points="{{ $caPoints }}"/>
                    <polyline fill="none" stroke="#DC2626" stroke-width="3" stroke-dasharray="5,4" points="{{ $depPoints }}"/>
                    <g font-size="10" fill="#6f7973">
                        @foreach($chart['labels'] as $i => $label)
                            <text x="{{ $xs[$i] - 10 }}" y="205">{{ ucfirst($label) }}</text>
                        @endforeach
                    </g>
                </svg>
                <div class="flex items-center gap-lg mt-sm text-xs">
                    <span class="flex items-center gap-xs text-outline"><span class="w-3 h-3 rounded-full bg-brand-emerald inline-block"></span>Chiffre d'affaires</span>
                    <span class="flex items-center gap-xs text-outline"><span class="w-3 h-3 rounded-full bg-error-red inline-block"></span>Dépenses</span>
                </div>
            @endif
        </div>
        <div class="lg:col-span-4 bg-white rounded-lg border border-outline-variant shadow-sm p-md">
            <h3 class="text-sm font-bold text-on-surface mb-md">Alertes Critiques</h3>
            @if(empty($this->alertesCritiques))
                <p class="text-xs text-outline text-center py-lg">Aucune alerte critique pour le moment.</p>
            @else
                <div class="space-y-sm">
                    @foreach($this->alertesCritiques as $alert)
                        <a href="{{ $alert['link'] }}" class="flex items-start gap-xs p-sm rounded-lg {{ $alert['severity'] === 'critique' ? 'bg-error-bg border border-error-deep/20 hover:bg-error-bg/70' : 'bg-accent-yellow/20 hover:bg-accent-yellow/30' }}">
                            <span class="material-symbols-outlined text-[18px] flex-shrink-0 {{ $alert['severity'] === 'critique' ? 'text-error-deep' : 'text-brand-forest' }}">warning</span>
                            <span class="text-xs font-semibold {{ $alert['severity'] === 'critique' ? 'text-error-deep' : 'text-brand-forest' }}">{{ $alert['label'] }}</span>
                        </a>
                    @endforeach
                </div>
            @endif
        </div>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-3 gap-md mb-lg">
        @if($this->cartesElevage === null)
            <div class="md:col-span-3 bg-white rounded-lg border border-outline-variant shadow-sm">
                <x-module-pending label="Les cartes élevage (Lapins, Volailles, Porcs)" since="Sprint 3 (Production Élevage & Soins)" />
            </div>
        @else
            @php $lapins = $this->cartesElevage['lapins']; @endphp
            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
                <div class="flex items-center gap-xs mb-sm"><span class="material-symbols-outlined text-brand-emerald">cruelty_free</span><h3 class="text-sm font-bold">Lapins</h3></div>
                <div class="grid grid-cols-2 gap-sm text-xs">
                    <div><p class="text-outline">Effectif</p><p class="font-bold text-lg">{{ number_format($lapins['effectif'], 0, ',', ' ') }}</p></div>
                    <div><p class="text-outline">Gestantes</p><p class="font-bold text-lg">{{ $lapins['gestantes'] }}</p></div>
                    <div><p class="text-outline">Marchands</p><p class="font-bold text-lg">{{ $lapins['marchands'] }}</p></div>
                    <div><p class="text-outline">Mortalité</p><p class="font-bold text-lg {{ $lapins['mortalite'] > 5 ? 'text-error-red' : 'text-brand-emerald' }}">{{ number_format($lapins['mortalite'], 1, ',', ' ') }}%</p></div>
                </div>
            </div>
            @php $volailles = $this->cartesElevage['volailles']; @endphp
            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
                <div class="flex items-center gap-xs mb-sm"><span class="material-symbols-outlined text-brand-emerald">egg</span><h3 class="text-sm font-bold">Volailles</h3></div>
                <div class="grid grid-cols-2 gap-sm text-xs">
                    <div><p class="text-outline">Lots actifs</p><p class="font-bold text-lg">{{ $volailles['lots_actifs'] }}</p></div>
                    <div><p class="text-outline">Taux ponte</p><p class="font-bold text-lg">{{ $volailles['taux_ponte'] }}%</p></div>
                    <div><p class="text-outline">Effectif</p><p class="font-bold text-lg">{{ number_format($volailles['effectif'], 0, ',', ' ') }}</p></div>
                    <div><p class="text-outline">Mortalité</p><p class="font-bold text-lg {{ $volailles['mortalite'] > 5 ? 'text-error-red' : 'text-brand-emerald' }}">{{ number_format($volailles['mortalite'], 1, ',', ' ') }}%</p></div>
                </div>
            </div>
            @php $porcs = $this->cartesElevage['porcs']; @endphp
            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
                <div class="flex items-center gap-xs mb-sm"><span class="material-symbols-outlined text-brand-emerald">pets</span><h3 class="text-sm font-bold">Porcs</h3></div>
                <div class="grid grid-cols-2 gap-sm text-xs">
                    <div><p class="text-outline">Effectif</p><p class="font-bold text-lg">{{ number_format($porcs['effectif'], 0, ',', ' ') }}</p></div>
                    <div><p class="text-outline">Gestantes</p><p class="font-bold text-lg">{{ $porcs['gestantes'] }}</p></div>
                    <div><p class="text-outline">Ventes (mois)</p><p class="font-bold text-lg">{{ $porcs['ventes_mois'] }}</p></div>
                    <div><p class="text-outline">Mortalité</p><p class="font-bold text-lg {{ $porcs['mortalite'] > 5 ? 'text-error-red' : 'text-brand-emerald' }}">{{ number_format($porcs['mortalite'], 1, ',', ' ') }}%</p></div>
                </div>
            </div>
        @endif
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-md mb-lg">
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
            <div class="flex items-center justify-between mb-md">
                <h3 class="text-sm font-bold text-on-surface flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">bar_chart</span>Statistiques de Ventes</h3>
                <span class="text-[10px] font-bold text-outline">{{ now()->year }}</span>
            </div>
            @if($this->chartVentesDepenses === null)
                <x-module-pending label="Ces statistiques" since="Sprints 4-5 (Ventes & Achats)" />
            @else
                @php
                    $chart = $this->chartVentesDepenses;
                    $curCa = end($chart['ca']); $prevCa = $chart['ca'][count($chart['ca']) - 2] ?? 0;
                    $curDep = end($chart['depenses']); $prevDep = $chart['depenses'][count($chart['depenses']) - 2] ?? 0;
                    $pctCa = $prevCa > 0 ? round((($curCa - $prevCa) / $prevCa) * 100, 1) : null;
                    $pctDep = $prevDep > 0 ? round((($curDep - $prevDep) / $prevDep) * 100, 1) : null;
                    $barMax = max(1, max(array_merge($chart['ca'], $chart['depenses'])));
                @endphp
                <div class="grid grid-cols-2 gap-sm mb-md">
                    <div class="bg-surface-zebra rounded-lg p-sm">
                        <span class="text-lg font-extrabold text-brand-emerald">{{ number_format($curCa, 0, ',', ' ') }} F</span>
                        <p class="text-[10px] text-outline">Revenu{{ $pctCa !== null ? ' ('.($pctCa >= 0 ? '+' : '').$pctCa.'%)' : '' }}</p>
                    </div>
                    <div class="bg-surface-zebra rounded-lg p-sm">
                        <span class="text-lg font-extrabold text-error-red">{{ number_format($curDep, 0, ',', ' ') }} F</span>
                        <p class="text-[10px] text-outline">Dépenses{{ $pctDep !== null ? ' ('.($pctDep >= 0 ? '+' : '').$pctDep.'%)' : '' }}</p>
                    </div>
                </div>
                <svg viewBox="0 0 500 140" class="w-full h-32">
                    <line x1="0" y1="120" x2="500" y2="120" stroke="#bec9c2" stroke-width="1"/>
                    <g>
                        @foreach($chart['labels'] as $i => $label)
                            @php
                                $groupX = 10 + $i * 50;
                                $caH = round(($chart['ca'][$i] / $barMax) * 100);
                                $depH = round(($chart['depenses'][$i] / $barMax) * 100);
                            @endphp
                            <rect x="{{ $groupX }}" y="{{ 120 - $caH }}" width="14" height="{{ max($caH, 1) }}" rx="3" fill="#065f46"/>
                            <rect x="{{ $groupX + 18 }}" y="{{ 120 - $depH }}" width="14" height="{{ max($depH, 1) }}" rx="3" fill="#DC2626"/>
                        @endforeach
                    </g>
                </svg>
                <div class="flex justify-between text-[9px] text-outline mt-xs px-1">
                    @foreach($chart['labels'] as $label)
                        <span>{{ ucfirst($label) }}</span>
                    @endforeach
                </div>
            @endif
        </div>

        <div x-data="{ tab: 'sale' }" class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
            <div class="flex items-center justify-between mb-md">
                <h3 class="text-sm font-bold text-on-surface flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">receipt_long</span>Transactions Récentes</h3>
                <a wire:navigate href="/ventes-devis" class="text-[10px] font-bold text-brand-emerald hover:underline">Voir tout</a>
            </div>
            <div class="flex items-center gap-xs mb-sm border-b border-outline-variant overflow-x-auto">
                <button type="button" @click="tab = 'sale'" :class="tab === 'sale' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline'" class="px-sm py-1.5 text-[11px] font-bold border-b-2 whitespace-nowrap">Vente</button>
                <button type="button" @click="tab = 'purchase'" :class="tab === 'purchase' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline'" class="px-sm py-1.5 text-[11px] font-bold border-b-2 whitespace-nowrap">Achat</button>
                <button type="button" @click="tab = 'quotation'" :class="tab === 'quotation' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline'" class="px-sm py-1.5 text-[11px] font-bold border-b-2 whitespace-nowrap">Devis</button>
                <button type="button" @click="tab = 'expenses'" :class="tab === 'expenses' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline'" class="px-sm py-1.5 text-[11px] font-bold border-b-2 whitespace-nowrap">Dépenses</button>
                <button type="button" @click="tab = 'invoices'" :class="tab === 'invoices' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline'" class="px-sm py-1.5 text-[11px] font-bold border-b-2 whitespace-nowrap">Factures</button>
            </div>
            @php $tx = $this->transactionsRecentes; @endphp
            <div x-show="tab === 'sale'">
                @if($tx['sale'] === null)
                    <x-module-pending label="Les ventes récentes" since="Sprint 4 (Ventes Ferme)" />
                @elseif($tx['sale']->isEmpty())
                    <p class="text-xs text-outline text-center py-md">Aucune vente récente.</p>
                @else
                    @foreach($tx['sale'] as $i => $sale)
                        <div class="flex items-center justify-between text-xs py-1.5 {{ $i < $tx['sale']->count() - 1 ? 'border-b border-outline-variant' : '' }}"><span>{{ strtoupper(substr($sale->id, 0, 8)) }} · {{ $sale->customer?->name ?? 'Client Anonyme' }}</span><span class="font-bold {{ $sale->payment_mode === 'credit' ? 'text-accent-yellow' : 'text-brand-emerald' }}">{{ number_format($sale->total, 0, ',', ' ') }} F</span></div>
                    @endforeach
                @endif
            </div>
            <div x-show="tab === 'purchase'" x-cloak>
                @if($tx['purchase'] === null)
                    <x-module-pending label="Les achats récents" since="Sprint 5 (Achats & Charges)" />
                @elseif($tx['purchase']->isEmpty())
                    <p class="text-xs text-outline text-center py-md">Aucun achat récent.</p>
                @else
                    @foreach($tx['purchase'] as $i => $purchase)
                        <div class="flex items-center justify-between text-xs py-1.5 {{ $i < $tx['purchase']->count() - 1 ? 'border-b border-outline-variant' : '' }}"><span>{{ strtoupper(substr($purchase->id, 0, 8)) }} · {{ $purchase->supplier?->name }}</span><span class="font-bold {{ $purchase->payment_mode === 'comptant' ? 'text-brand-forest' : 'text-accent-yellow' }}">{{ number_format($purchase->total, 0, ',', ' ') }} F</span></div>
                    @endforeach
                @endif
            </div>
            <div x-show="tab === 'quotation'" x-cloak>
                @if($tx['quotation'] === null)
                    <x-module-pending label="Les devis récents" since="Sprint 4 (Ventes Ferme)" />
                @elseif($tx['quotation']->isEmpty())
                    <p class="text-xs text-outline text-center py-md">Aucun devis récent.</p>
                @else
                    @foreach($tx['quotation'] as $i => $quote)
                        <div class="flex items-center justify-between text-xs py-1.5 {{ $i < $tx['quotation']->count() - 1 ? 'border-b border-outline-variant' : '' }}"><span>{{ strtoupper(substr($quote->id, 0, 8)) }} · {{ $quote->customer?->name }}</span><span class="font-bold text-info-blue">{{ number_format($quote->amount, 0, ',', ' ') }} F</span></div>
                    @endforeach
                @endif
            </div>
            <div x-show="tab === 'expenses'" x-cloak>
                @if($tx['expenses'] === null)
                    <x-module-pending label="Les dépenses récentes" since="Sprint 5 (Achats & Charges)" />
                @elseif($tx['expenses']->isEmpty())
                    <p class="text-xs text-outline text-center py-md">Aucune dépense récente.</p>
                @else
                    @foreach($tx['expenses'] as $i => $expense)
                        <div class="flex items-center justify-between text-xs py-1.5 {{ $i < $tx['expenses']->count() - 1 ? 'border-b border-outline-variant' : '' }}"><span>{{ $expense->label }}</span><span class="font-bold text-error-red">{{ number_format($expense->amount, 0, ',', ' ') }} F</span></div>
                    @endforeach
                @endif
            </div>
            <div x-show="tab === 'invoices'" x-cloak>
                @if($tx['invoices'] === null)
                    <x-module-pending label="Les factures récentes" since="Sprint 7 (Facturation)" />
                @elseif($tx['invoices']->isEmpty())
                    <p class="text-xs text-outline text-center py-md">Aucune facture récente.</p>
                @else
                    @foreach($tx['invoices'] as $i => $invoice)
                        <div class="flex items-center justify-between text-xs py-1.5 {{ $i < $tx['invoices']->count() - 1 ? 'border-b border-outline-variant' : '' }}"><span>{{ strtoupper(substr($invoice->id, 0, 8)) }} · {{ $invoice->customer?->name ?? 'Client Anonyme' }}</span><span class="font-bold {{ $invoice->payment_mode === 'credit' ? 'text-accent-yellow' : 'text-brand-emerald' }}">{{ number_format($invoice->total, 0, ',', ' ') }} F</span></div>
                    @endforeach
                @endif
            </div>
        </div>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-md">
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
            <h3 class="text-sm font-bold text-on-surface mb-md">Activités du Jour</h3>
            @if($this->activitesJour->isEmpty())
                <p class="text-xs text-outline text-center py-lg">Aucune activité enregistrée aujourd'hui pour le moment.</p>
            @else
                <div class="space-y-md">
                    @foreach($this->activitesJour as $entry)
                        <div class="flex gap-sm">
                            <span class="w-2 h-2 rounded-full bg-brand-emerald mt-1.5"></span>
                            <div>
                                <p class="text-xs font-semibold">{{ $entry->action_label }}</p>
                                <p class="text-[10px] text-outline">{{ $entry->created_at->format('H:i') }} — {{ $entry->user?->name ?? 'Système' }}@if($entry->module_label) · {{ $entry->module_label }} @endif</p>
                            </div>
                        </div>
                    @endforeach
                </div>
            @endif
        </div>
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md overflow-x-auto">
            <h3 class="text-sm font-bold text-on-surface mb-md">Top 5 Produits du Mois</h3>
            @if($this->topProduits === null)
                <x-module-pending label="Ce classement" since="Sprint 4 (Ventes Ferme)" />
            @elseif(empty($this->topProduits))
                <p class="text-xs text-outline text-center py-lg">Aucune vente ce mois-ci.</p>
            @else
                <table class="w-full text-xs">
                    <thead><tr class="text-outline border-b border-outline-variant"><th class="text-left py-xs">Produit</th><th class="text-right py-xs">Qté</th><th class="text-right py-xs">CA</th><th class="text-right py-xs">Marge</th></tr></thead>
                    <tbody>
                        @foreach($this->topProduits as $i => $row)
                            <tr class="border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : '' }}">
                                <td class="py-xs">{{ $row['product']?->name ?? '—' }}</td>
                                <td class="text-right">{{ rtrim(rtrim(number_format($row['qty'], 2, '.', ''), '0'), '.') }}</td>
                                <td class="text-right">{{ number_format($row['ca'], 0, ',', ' ') }}</td>
                                <td class="text-right {{ $row['marge_pct'] !== null ? 'text-brand-emerald' : 'text-outline' }}">{{ $row['marge_pct'] !== null ? $row['marge_pct'].'%' : '—' }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            @endif
        </div>
    </div>

</div>
