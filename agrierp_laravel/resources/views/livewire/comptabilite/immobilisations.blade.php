<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">domain</span>Immobilisations
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Registre des biens durables, amortissement linéaire et dotation comptable — source de la Note 2 des États Financiers.</p>
        </div>
        @can('manage-comptabilite')
            <button type="button" wire:click="nouveau" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all">
                <span class="material-symbols-outlined text-[18px]">add</span>Nouvelle Immobilisation
            </button>
        @endcan
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-lg flex flex-wrap items-end gap-md">
        <div>
            <label for="immo-date" class="text-[10px] text-brand-forest font-bold uppercase block mb-xs">Date d'arrêté</label>
            <input id="immo-date" type="date" wire:model.live="dateArrete" class="text-sm font-bold border border-outline-variant rounded-lg px-md py-2 bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
        </div>
        <div>
            <label for="immo-nature" class="text-[10px] text-brand-forest font-bold uppercase block mb-xs">Nature</label>
            <select id="immo-nature" wire:model.live="filtreNature" class="text-sm font-bold border border-outline-variant rounded-lg px-md py-2 bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
                <option value="tous">Toutes les natures</option>
                @foreach($this->natures as $nature)
                    <option value="{{ $nature->code }}">{{ $nature->code }} — {{ $nature->label }}</option>
                @endforeach
            </select>
        </div>
        <div>
            <label for="immo-statut" class="text-[10px] text-brand-forest font-bold uppercase block mb-xs">Statut</label>
            <select id="immo-statut" wire:model.live="filtreStatut" class="text-sm font-bold border border-outline-variant rounded-lg px-md py-2 bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
                <option value="en_service">En service</option>
                <option value="cede">Cédées</option>
                <option value="reforme">Réformées</option>
                <option value="tous">Tous statuts</option>
            </select>
        </div>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-4 gap-md mb-lg">
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-emerald shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">Valeur Brute</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ number_format($this->kpis['brut'], 0, ',', ' ') }} F</span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-error-red shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">Amortissements Cumulés</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs text-error-deep">−{{ number_format($this->kpis['amortissement'], 0, ',', ' ') }} F</span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-forest shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">Valeur Nette Comptable</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs text-brand-forest">{{ number_format($this->kpis['net'], 0, ',', ' ') }} F</span>
        </div>
        <div class="p-md rounded-lg border shadow-sm {{ $this->kpis['a_doter'] > 0 ? 'border-accent-yellow/40 bg-accent-yellow/10' : 'border-outline-variant bg-white' }}">
            <span class="text-[10px] text-outline font-bold uppercase block">Dotation à Comptabiliser</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ number_format($this->kpis['a_doter'], 0, ',', ' ') }} F</span>
        </div>
    </div>

    @if($this->kpis['hors_compta'] > 0)
        <div class="bg-white border border-outline-variant rounded-lg p-md mb-lg flex items-start gap-sm">
            <span class="material-symbols-outlined text-outline text-[20px]">info</span>
            <div>
                <p class="text-xs font-bold text-brand-forest">{{ number_format($this->kpis['hors_compta'], 0, ',', ' ') }} FCFA hors comptabilité</p>
                <p class="text-[11px] text-outline mt-xs">
                    Des biens saisis en reprise d'antériorité figurent à ce registre sans écriture de classe 2 : ils n'apparaissent donc pas à l'Actif Immobilisé du Bilan et ne sont pas amortis au grand livre.
                    Leur valeur relève d'un bilan d'ouverture que l'application n'importe pas encore.
                </p>
            </div>
        </div>
    @endif

    @can('manage-comptabilite')
        @if($this->kpis['a_doter'] > 0)
            <div class="bg-accent-yellow/10 border border-accent-yellow/40 rounded-lg p-md mb-lg flex flex-col sm:flex-row sm:items-center sm:justify-between gap-sm">
                <div class="flex items-start gap-sm">
                    <span class="material-symbols-outlined text-brand-forest text-[20px]">calculate</span>
                    <div>
                        <p class="text-xs font-bold text-brand-forest">Dotation aux amortissements en attente</p>
                        <p class="text-[11px] text-outline mt-xs">
                            {{ number_format($this->kpis['a_doter'], 0, ',', ' ') }} FCFA d'amortissement calculé au {{ \Carbon\Carbon::parse($this->dateArrete)->format('d/m/Y') }} ne sont pas encore comptabilisés.
                            L'écriture débitera <span class="font-mono font-bold">681</span> et créditera <span class="font-mono font-bold">281</span>.
                        </p>
                    </div>
                </div>
                <button type="button" wire:click="passerDotation" wire:loading.attr="disabled" wire:target="passerDotation" class="shrink-0 flex items-center justify-center gap-xs bg-brand-forest hover:bg-brand-emerald text-white font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
                    <span class="material-symbols-outlined text-[18px]">post_add</span>Passer la Dotation
                </button>
            </div>
        @endif
    @endcan

    @if(count($this->ventilation) > 0)
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden mb-lg">
            <div class="px-md py-sm border-b border-outline-variant bg-surface-zebra">
                <h3 class="text-sm font-bold text-brand-forest">Ventilation par Nature d'Actif</h3>
                <p class="text-[11px] text-outline">Alimente la Note 2 des États Financiers — au {{ \Carbon\Carbon::parse($this->dateArrete)->format('d/m/Y') }}, biens en service uniquement.</p>
            </div>
            <div class="overflow-x-auto">
                <table class="w-full rtable">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Compte</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Nature</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Nb</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Valeur Brute</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Amortissement</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Valeur Nette</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach($this->ventilation as $i => $ligne)
                            <tr class="rrow border-b border-outline-variant {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                                <td data-label="Compte" class="px-md py-sm text-xs font-mono font-bold">{{ $ligne['code'] }}</td>
                                <td data-label="Nature" class="px-md py-sm text-xs">{{ $ligne['label'] }}</td>
                                <td data-label="Nb" class="px-md py-sm text-xs text-right">{{ $ligne['nombre'] }}</td>
                                <td data-label="Valeur Brute" class="px-md py-sm text-xs text-right">{{ number_format($ligne['brut'], 0, ',', ' ') }}</td>
                                <td data-label="Amortissement" class="px-md py-sm text-xs text-right text-error-deep">{{ $ligne['amortissement'] > 0 ? '−'.number_format($ligne['amortissement'], 0, ',', ' ') : '—' }}</td>
                                <td data-label="Valeur Nette" class="px-md py-sm text-xs text-right font-bold text-brand-forest">{{ number_format($ligne['net'], 0, ',', ' ') }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                    <tfoot>
                        <tr class="bg-brand-forest text-white font-bold">
                            <td class="px-md py-sm text-xs" colspan="3">TOTAL IMMOBILISATIONS</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($this->kpis['brut'], 0, ',', ' ') }}</td>
                            <td class="px-md py-sm text-xs text-right">−{{ number_format($this->kpis['amortissement'], 0, ',', ' ') }}</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($this->kpis['net'], 0, ',', ' ') }}</td>
                        </tr>
                    </tfoot>
                </table>
            </div>
        </div>
    @endif

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="px-md py-sm border-b border-outline-variant bg-surface-zebra">
            <h3 class="text-sm font-bold text-brand-forest">Registre Détaillé</h3>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Code</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Désignation</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Acquisition</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Valeur Brute</th>
                        <th class="px-md py-sm text-center text-[10px] text-outline font-bold uppercase">Durée</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Annuité</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Cumul Amort.</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">V.N.C.</th>
                        <th class="px-md py-sm text-center text-[10px] text-outline font-bold uppercase">Comptabilisé</th>
                        <th class="px-md py-sm text-center text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->biens as $i => $bien)
                        <tr class="rrow border-b border-outline-variant {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                            <td data-label="Code" class="px-md py-sm text-xs font-mono font-bold">{{ $bien->code }}</td>
                            <td data-label="Désignation" class="px-md py-sm text-xs">
                                <span class="font-bold text-brand-forest">{{ $bien->label }}</span>
                                <span class="block text-[10px] text-outline font-mono">Compte {{ $bien->account_code }}</span>
                            </td>
                            <td data-label="Acquisition" class="px-md py-sm text-xs">{{ $bien->acquisition_date->format('d/m/Y') }}</td>
                            <td data-label="Valeur Brute" class="px-md py-sm text-xs text-right">{{ number_format((float) $bien->acquisition_value, 0, ',', ' ') }}</td>
                            <td data-label="Durée" class="px-md py-sm text-xs text-center">{{ $bien->duration_years }} ans</td>
                            <td data-label="Annuité" class="px-md py-sm text-xs text-right">{{ number_format($bien->annuite(), 0, ',', ' ') }}</td>
                            <td data-label="Cumul Amort." class="px-md py-sm text-xs text-right text-error-deep">
                                {{ number_format($bien->cumulAmortissement($this->dateArrete), 0, ',', ' ') }}
                                @if($bien->estTotalementAmorti($this->dateArrete))
                                    <span class="block text-[10px] text-outline font-bold uppercase">Amorti</span>
                                @endif
                            </td>
                            <td data-label="V.N.C." class="px-md py-sm text-xs text-right font-bold text-brand-forest">{{ number_format($bien->valeurNette($this->dateArrete), 0, ',', ' ') }}</td>
                            <td data-label="Comptabilisé" class="px-md py-sm text-xs text-center">
                                @if($bien->is_capitalized)
                                    <span class="material-symbols-outlined text-brand-emerald text-[18px]" title="Porté à l'actif">check_circle</span>
                                @else
                                    <span class="material-symbols-outlined text-outline text-[18px]" title="Reprise d'antériorité — hors comptabilité">remove_circle_outline</span>
                                @endif
                            </td>
                            <td data-label="Statut" class="px-md py-sm text-xs text-center">
                                @if($bien->status === 'en_service')
                                    <span class="inline-block px-sm py-0.5 rounded-full text-[10px] font-bold bg-brand-emerald/10 text-brand-emerald">En service</span>
                                @elseif($bien->status === 'cede')
                                    <span class="inline-block px-sm py-0.5 rounded-full text-[10px] font-bold bg-outline/10 text-outline">Cédée {{ $bien->disposal_date?->format('d/m/Y') }}</span>
                                @else
                                    <span class="inline-block px-sm py-0.5 rounded-full text-[10px] font-bold bg-error-red/10 text-error-deep">Réformée {{ $bien->disposal_date?->format('d/m/Y') }}</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-xs text-right whitespace-nowrap">
                                @can('manage-comptabilite')
                                    <button type="button" wire:click="editer('{{ $bien->id }}')" class="text-brand-emerald hover:text-brand-forest font-bold" title="Modifier">
                                        <span class="material-symbols-outlined text-[18px] align-middle">edit</span>
                                    </button>
                                    @if($bien->status === 'en_service')
                                        <button type="button" wire:click="ouvrirCession('{{ $bien->id }}')" class="text-outline hover:text-error-deep font-bold ml-xs" title="Cession / réforme">
                                            <span class="material-symbols-outlined text-[18px] align-middle">logout</span>
                                        </button>
                                    @endif
                                @else
                                    <span class="text-outline">—</span>
                                @endcan
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="11" class="px-md py-lg text-center text-outline">Aucune immobilisation enregistrée pour ce filtre.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    @if($showForm)
        <div class="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-md" wire:key="form-immo">
            <div class="bg-white rounded-lg shadow-xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
                <div class="px-md py-sm border-b border-outline-variant flex items-center justify-between">
                    <h3 class="text-sm font-bold text-brand-forest">{{ $editingId ? 'Modifier l\'Immobilisation' : 'Nouvelle Immobilisation' }}</h3>
                    <button type="button" wire:click="$set('showForm', false)" class="text-outline hover:text-error-deep">
                        <span class="material-symbols-outlined text-[20px]">close</span>
                    </button>
                </div>
                <form wire:submit="enregistrer" class="p-md grid grid-cols-1 sm:grid-cols-2 gap-md">
                    <div>
                        <label for="immo-code" class="text-[10px] text-brand-forest font-bold uppercase block mb-xs">Code *</label>
                        <input id="immo-code" type="text" wire:model="code" placeholder="IMM-001" class="w-full text-sm border border-outline-variant rounded-lg px-md py-2 focus:ring-2 focus:ring-brand-emerald outline-none">
                        @error('code') <span class="text-[11px] text-error-deep">{{ $message }}</span> @enderror
                    </div>
                    <div>
                        <label for="immo-label" class="text-[10px] text-brand-forest font-bold uppercase block mb-xs">Désignation *</label>
                        <input id="immo-label" type="text" wire:model="label" placeholder="Broyeur à provende" class="w-full text-sm border border-outline-variant rounded-lg px-md py-2 focus:ring-2 focus:ring-brand-emerald outline-none">
                        @error('label') <span class="text-[11px] text-error-deep">{{ $message }}</span> @enderror
                    </div>
                    <div class="sm:col-span-2">
                        <label for="immo-compte" class="text-[10px] text-brand-forest font-bold uppercase block mb-xs">Nature (compte de classe 2) *</label>
                        <select id="immo-compte" wire:model="accountCode" class="w-full text-sm border border-outline-variant rounded-lg px-md py-2 bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
                            <option value="">— Choisir —</option>
                            @foreach($this->natures as $nature)
                                <option value="{{ $nature->code }}">{{ $nature->code }} — {{ $nature->label }}</option>
                            @endforeach
                        </select>
                        @error('accountCode') <span class="text-[11px] text-error-deep">{{ $message }}</span> @enderror
                    </div>
                    <div>
                        <label for="immo-acq-date" class="text-[10px] text-brand-forest font-bold uppercase block mb-xs">Date d'acquisition *</label>
                        <input id="immo-acq-date" type="date" wire:model="acquisitionDate" class="w-full text-sm border border-outline-variant rounded-lg px-md py-2 focus:ring-2 focus:ring-brand-emerald outline-none">
                        @error('acquisitionDate') <span class="text-[11px] text-error-deep">{{ $message }}</span> @enderror
                    </div>
                    <div>
                        <label for="immo-valeur" class="text-[10px] text-brand-forest font-bold uppercase block mb-xs">Valeur d'acquisition (FCFA) *</label>
                        <input id="immo-valeur" type="number" step="1" min="1" wire:model="acquisitionValue" class="w-full text-sm border border-outline-variant rounded-lg px-md py-2 focus:ring-2 focus:ring-brand-emerald outline-none">
                        @error('acquisitionValue') <span class="text-[11px] text-error-deep">{{ $message }}</span> @enderror
                    </div>
                    <div>
                        <label for="immo-residu" class="text-[10px] text-brand-forest font-bold uppercase block mb-xs">Valeur résiduelle (FCFA)</label>
                        <input id="immo-residu" type="number" step="1" min="0" wire:model="residualValue" class="w-full text-sm border border-outline-variant rounded-lg px-md py-2 focus:ring-2 focus:ring-brand-emerald outline-none">
                        @error('residualValue') <span class="text-[11px] text-error-deep">{{ $message }}</span> @enderror
                    </div>
                    <div>
                        <label for="immo-duree" class="text-[10px] text-brand-forest font-bold uppercase block mb-xs">Durée d'amortissement (ans) *</label>
                        <input id="immo-duree" type="number" step="1" min="1" max="50" wire:model="durationYears" class="w-full text-sm border border-outline-variant rounded-lg px-md py-2 focus:ring-2 focus:ring-brand-emerald outline-none">
                        @error('durationYears') <span class="text-[11px] text-error-deep">{{ $message }}</span> @enderror
                    </div>
                    @unless($editingId)
                        <div class="sm:col-span-2">
                            <label for="immo-contrepartie" class="text-[10px] text-brand-forest font-bold uppercase block mb-xs">Comptabilisation de l'acquisition</label>
                            <select id="immo-contrepartie" wire:model="contrepartie" class="w-full text-sm border border-outline-variant rounded-lg px-md py-2 bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
                                <option value="">Reprise d'antériorité — aucune écriture</option>
                                @foreach($this->comptesTresorerie as $compte)
                                    <option value="{{ $compte->id }}">Payé par {{ $compte->label }} ({{ $compte->account_code }})</option>
                                @endforeach
                                <option value="credit">À crédit — dette fournisseur (401)</option>
                            </select>
                            @error('contrepartie') <span class="text-[11px] text-error-deep">{{ $message }}</span> @enderror
                            <p class="text-[11px] text-outline mt-xs">
                                Une acquisition comptabilisée débite le compte de classe 2 choisi et crédite la contrepartie. Sans écriture, le bien alimente ce registre mais reste absent du Bilan.
                            </p>
                        </div>
                    @endunless

                    <div class="sm:col-span-2 flex items-center justify-end gap-sm border-t border-outline-variant pt-md">
                        <button type="button" wire:click="$set('showForm', false)" class="text-xs font-bold text-outline hover:text-brand-forest px-md py-sm">Annuler</button>
                        <button type="submit" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all">
                            <span class="material-symbols-outlined text-[18px]">save</span>Enregistrer
                        </button>
                    </div>
                </form>
            </div>
        </div>
    @endif

    @if($showCession)
        <div class="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-md" wire:key="cession-immo">
            <div class="bg-white rounded-lg shadow-xl w-full max-w-md">
                <div class="px-md py-sm border-b border-outline-variant flex items-center justify-between">
                    <h3 class="text-sm font-bold text-brand-forest">Sortie d'Immobilisation</h3>
                    <button type="button" wire:click="$set('showCession', false)" class="text-outline hover:text-error-deep">
                        <span class="material-symbols-outlined text-[20px]">close</span>
                    </button>
                </div>
                <form wire:submit="confirmerCession" class="p-md flex flex-col gap-md">
                    <p class="text-[11px] text-outline">Le bien n'est jamais supprimé : il change de statut et cesse de s'amortir à la date de sortie, son historique comptable restant consultable.</p>
                    <div>
                        <label for="cess-statut" class="text-[10px] text-brand-forest font-bold uppercase block mb-xs">Type de sortie *</label>
                        <select id="cess-statut" wire:model="cessionStatus" class="w-full text-sm border border-outline-variant rounded-lg px-md py-2 bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
                            <option value="cede">Cession (vente)</option>
                            <option value="reforme">Réforme (mise au rebut)</option>
                        </select>
                    </div>
                    <div>
                        <label for="cess-date" class="text-[10px] text-brand-forest font-bold uppercase block mb-xs">Date de sortie *</label>
                        <input id="cess-date" type="date" wire:model="cessionDate" class="w-full text-sm border border-outline-variant rounded-lg px-md py-2 focus:ring-2 focus:ring-brand-emerald outline-none">
                        @error('cessionDate') <span class="text-[11px] text-error-deep">{{ $message }}</span> @enderror
                    </div>
                    <div>
                        <label for="cess-motif" class="text-[10px] text-brand-forest font-bold uppercase block mb-xs">Motif *</label>
                        <input id="cess-motif" type="text" wire:model="cessionReason" placeholder="Vendu à un éleveur voisin" class="w-full text-sm border border-outline-variant rounded-lg px-md py-2 focus:ring-2 focus:ring-brand-emerald outline-none">
                        @error('cessionReason') <span class="text-[11px] text-error-deep">{{ $message }}</span> @enderror
                    </div>
                    <div class="flex items-center justify-end gap-sm border-t border-outline-variant pt-md">
                        <button type="button" wire:click="$set('showCession', false)" class="text-xs font-bold text-outline hover:text-brand-forest px-md py-sm">Annuler</button>
                        <button type="submit" class="flex items-center gap-xs bg-brand-forest hover:bg-error-deep text-white font-bold text-xs px-md py-sm rounded-full transition-all">
                            <span class="material-symbols-outlined text-[18px]">logout</span>Confirmer la Sortie
                        </button>
                    </div>
                </form>
            </div>
        </div>
    @endif
</div>
