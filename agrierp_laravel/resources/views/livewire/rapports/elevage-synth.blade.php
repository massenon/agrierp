<div class="mt-md">
    <div class="mb-md">
        <select wire:model.live="lotFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">Lot / Souche : Tous</option>
            @foreach($this->lots as $lot)
                <option value="{{ $lot->id }}">{{ $lot->code }}</option>
            @endforeach
        </select>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-md mb-md">
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-emerald shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">Production Totale (Œufs)</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ number_format($this->kpis['production_totale'], 0, ',', ' ') }}</span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-info-blue shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">Taux de Ponte Moyen</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ $this->kpis['taux_ponte_moyen'] !== null ? $this->kpis['taux_ponte_moyen'].' %' : '—' }}</span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-error-red shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">Taux de Mortalité Hebdo</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ $this->kpis['taux_mortalite_hebdo'] !== null ? $this->kpis['taux_mortalite_hebdo'].' %' : '—' }}</span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-accent-yellow shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">CA Ventes du Lot</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ number_format($this->kpis['ca_ventes'], 0, ',', ' ') }} <span class="text-xs font-normal text-outline">FCFA</span></span>
        </div>
    </div>

    <div class="flex items-center gap-xs mb-md overflow-x-auto">
        <button type="button" wire:click="$set('activeTable', 't1')" class="px-md py-2 rounded-full text-xs font-bold whitespace-nowrap flex-shrink-0 {{ $activeTable === 't1' ? 'bg-brand-emerald text-white' : 'border border-outline-variant text-outline' }}">Tableau 1 : Recensement</button>
        <button type="button" wire:click="$set('activeTable', 't2')" class="px-md py-2 rounded-full text-xs font-bold whitespace-nowrap flex-shrink-0 {{ $activeTable === 't2' ? 'bg-brand-emerald text-white' : 'border border-outline-variant text-outline' }}">Tableau 2 : Mouvements, Traitements &amp; Ventes</button>
        <button type="button" wire:click="$set('activeTable', 't3')" class="px-md py-2 rounded-full text-xs font-bold whitespace-nowrap flex-shrink-0 {{ $activeTable === 't3' ? 'bg-brand-emerald text-white' : 'border border-outline-variant text-outline' }}">Tableau 3 : Suivi de la Ponte</button>
    </div>

    @if($activeTable === 't1')
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <p class="text-[10px] text-outline px-md py-sm border-b border-outline-variant italic">Colonnes réellement disponibles depuis les fiches journalières — la ventilation détaillée par rôle de reproduction (Mères Pondeuses/Couveuses/Éleveuses, Géniteurs) n'existe pas dans un schéma commun à toutes les espèces et n'est pas approximée ici.</p>
            <div class="overflow-x-auto">
                <table class="w-full text-xs">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="sticky left-0 bg-surface-zebra z-10 px-sm py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Date</th>
                            <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Lot / Souche</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase">Effectif M</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Effectif F</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase">Sous Mères</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Sevrés</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase">Achats</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Nés</th>
                            <th class="px-sm py-sm text-center text-[10px] text-error-deep font-bold uppercase">Morts</th>
                            <th class="px-sm py-sm text-center text-[10px] text-brand-emerald font-bold uppercase">Effectif Final</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($this->entries as $i => $e)
                            <tr class="{{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} border-b border-outline-variant">
                                <td class="sticky left-0 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} z-10 px-sm py-sm font-bold text-brand-forest border-r border-outline-variant">{{ $e->entry_date->format('d/m/Y') }}</td>
                                <td class="px-sm py-sm font-bold text-brand-emerald border-r border-outline-variant">{{ $e->lot?->code }}</td>
                                <td class="px-sm py-sm text-center">{{ $e->effectif_m }}</td>
                                <td class="px-sm py-sm text-center border-r border-outline-variant">{{ $e->effectif_f }}</td>
                                <td class="px-sm py-sm text-center">{{ $e->effectif_smeres }}</td>
                                <td class="px-sm py-sm text-center border-r border-outline-variant">{{ $e->effectif_sevres }}</td>
                                <td class="px-sm py-sm text-center">{{ $e->achat }}</td>
                                <td class="px-sm py-sm text-center border-r border-outline-variant">{{ $e->ne }}</td>
                                <td class="px-sm py-sm text-center text-error-deep font-bold">{{ $e->mort }}</td>
                                <td class="px-sm py-sm text-center font-bold text-brand-emerald">{{ $e->effectif_final }}</td>
                            </tr>
                        @empty
                            <tr><td colspan="10" class="px-md py-lg text-center text-outline">Aucune fiche journalière sur la période.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
            <p class="text-[10px] text-outline px-md py-sm border-t border-outline-variant">Formule : Taux Mortalité Hebdo (%) = (Cumul Morts ÷ Effectif Début) × 100</p>
        </div>
    @endif

    @if($activeTable === 't2')
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <div class="overflow-x-auto">
                <table class="w-full text-xs">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="sticky left-0 bg-surface-zebra z-10 px-sm py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Date</th>
                            <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Lot</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase">Sexe Vendu</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase">Qté Vendue</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Montant Vente (FCFA)</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Effectif Final</th>
                            <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">Traitement Administré</th>
                            <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Dose</th>
                            <th class="px-sm py-sm text-left text-[10px] text-error-deep font-bold uppercase">Signes de Maladie Observés</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($this->entries as $i => $e)
                            <tr class="{{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} border-b border-outline-variant">
                                <td class="sticky left-0 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} z-10 px-sm py-sm font-bold text-brand-forest border-r border-outline-variant">{{ $e->entry_date->format('d/m/Y') }}</td>
                                <td class="px-sm py-sm font-bold text-brand-emerald border-r border-outline-variant">{{ $e->lot?->code }}</td>
                                <td class="px-sm py-sm text-center">{{ $e->vente_sexe ?? '—' }}</td>
                                <td class="px-sm py-sm text-center">{{ $e->vente }}</td>
                                <td class="px-sm py-sm text-right font-bold border-r border-outline-variant">{{ number_format($e->vente_montant, 0, ',', ' ') }}</td>
                                <td class="px-sm py-sm text-center font-bold text-brand-emerald border-r border-outline-variant">{{ $e->effectif_final }}</td>
                                <td class="px-sm py-sm">{{ $e->treatmentProduct?->name ?? '—' }}</td>
                                <td class="px-sm py-sm border-r border-outline-variant">{{ $e->treatment_dose ?? '—' }}</td>
                                <td class="px-sm py-sm text-outline">{{ $e->symptomes ?: 'RAS' }}</td>
                            </tr>
                        @empty
                            <tr><td colspan="9" class="px-md py-lg text-center text-outline">Aucune fiche journalière sur la période.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
            <p class="text-[10px] text-outline px-md py-sm border-t border-outline-variant">Formules : Recette Ventes (FCFA) = Qté Vendue × Prix Unitaire — Effectif Final = Effectif Début − (Morts + Ventes + Dons)</p>
        </div>
    @endif

    @if($activeTable === 't3')
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <p class="text-[10px] text-outline px-md py-sm border-b border-outline-variant italic">Les quatre colonnes de stock (SRH / TS / OS / Stock Final) sont des soldes de <strong>ferme</strong>, en plateaux : le stock d'œufs est tenu au niveau du produit, rien ne distingue l'œuf issu d'une bande de celui issu d'une autre. Deux bandes pondeuses le même jour affichent donc le même solde.</p>
            <div class="overflow-x-auto">
                <table class="w-full text-xs">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="sticky left-0 bg-surface-zebra z-10 px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Âge (Sem.)</th>
                            <th class="px-sm py-sm text-center text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Jour</th>
                            <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Lot</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase">Total Œufs Récoltés (OR)</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Taux Ponte %</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase">Cassés/Fêlés (OF)</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Commercialisables (OR-OF)</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase">Stock Restant Hier (SRH)</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase border-r border-outline-variant">Total Stock (TS)</th>
                            <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase">Sorties Vente OS (Plateaux)</th>
                            <th class="px-sm py-sm text-right text-[10px] text-brand-emerald font-bold uppercase">Stock Final (Plateaux + Vrac)</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($this->entries->where('ponte_total', '>', 0) as $i => $e)
                            <tr class="{{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} border-b border-outline-variant">
                                <td class="sticky left-0 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} z-10 px-sm py-sm text-center font-bold text-brand-forest border-r border-outline-variant">{{ $e->lot?->created_date ? intdiv($e->lot->created_date->diffInDays($e->entry_date), 7) : '—' }}</td>
                                <td class="px-sm py-sm text-center border-r border-outline-variant">{{ $e->entry_date->format('d/m/Y') }}</td>
                                <td class="px-sm py-sm font-bold text-brand-emerald border-r border-outline-variant">{{ $e->lot?->code }}</td>
                                <td class="px-sm py-sm text-right font-bold text-brand-emerald">{{ $e->ponte_total }}</td>
                                <td class="px-sm py-sm text-right font-bold border-r border-outline-variant">{{ $e->effectif_final > 0 ? number_format(($e->ponte_total / $e->effectif_final) * 100, 1) : '—' }} %</td>
                                <td class="px-sm py-sm text-right text-error-deep">{{ $e->ponte_casses }}</td>
                                <td class="px-sm py-sm text-right font-bold border-r border-outline-variant">{{ $e->ponte_total - $e->ponte_casses }}</td>
                                @php($l = $this->ledgerOeufs[$e->entry_date->format('Y-m-d')] ?? null)
                                <td class="px-sm py-sm text-right">{{ $l ? number_format($l['srh'], 0, ',', ' ') : '—' }}</td>
                                <td class="px-sm py-sm text-right font-bold border-r border-outline-variant">{{ $l ? number_format($l['ts'], 0, ',', ' ') : '—' }}</td>
                                <td class="px-sm py-sm text-right">{{ $l ? number_format($l['os'], 0, ',', ' ') : '—' }}</td>
                                <td class="px-sm py-sm text-right font-bold text-brand-emerald">{{ $l ? number_format($l['final'], 0, ',', ' ').' plateaux'.($l['vrac'] > 0 ? ' + '.$l['vrac'].' vrac' : '') : '—' }}</td>
                            </tr>
                        @empty
                            <tr><td colspan="11" class="px-md py-lg text-center text-outline">Aucune ponte enregistrée sur la période.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
            <p class="text-[10px] text-outline px-md py-sm border-t border-outline-variant">Formules : Taux de Ponte % = (OR × 100) ÷ Effectif Fin — Total Stock (TS) = (OR−OF) + SRH — Stock Final = TS − OS</p>
        </div>
    @endif
</div>
