<div>
    <div class="border-b border-outline-variant pb-md mb-lg flex flex-col sm:flex-row sm:items-center sm:justify-between gap-sm">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">event_repeat</span>Bascule &amp; Clôture d'Exercice Comptable
            </h2>
            <p class="text-xs text-outline mt-xs">Sélection de l'exercice fiscal actif et assistant de clôture annuelle (N vers N+1).</p>
        </div>
        <button type="button" wire:click="exportClotureExercicePdf" wire:loading.attr="disabled" wire:target="exportClotureExercicePdf" class="flex items-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
        </button>
    </div>

    <div class="flex items-center gap-xs border-b border-outline-variant mb-md overflow-x-auto">
        <button type="button" wire:click="$set('tab', 'periodique')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'periodique' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">Cl&ocirc;ture P&eacute;riodique</button>
        <button type="button" wire:click="$set('tab', 'annuelle')" dusk="tab-annuelle" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'annuelle' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">Cl&ocirc;ture Annuelle</button>
    </div>

@if($tab === 'periodique')
    <p class="text-xs text-outline mb-md">Verrouillage mensuel l&eacute;ger &mdash; n'affecte pas le Report &agrave; Nouveau. Un d&eacute;blocage exceptionnel reste possible pour le r&ocirc;le Administrateur uniquement.</p>

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-lg flex flex-wrap items-center gap-sm">
        <label for="periodique-mois-select" class="text-[10px] text-brand-forest font-bold uppercase">Mois &agrave; cl&ocirc;turer :</label>
        <select id="periodique-mois-select" wire:model.live="periodeACloturer" class="text-sm font-bold border border-outline-variant rounded-lg px-md py-2 bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
            @foreach($this->periodesCloturables as $value => $label)
                <option value="{{ $value }}">{{ $label }}</option>
            @endforeach
        </select>
    </div>

    @if(! $this->periodeBalance['is_balanced'])
        <div class="bg-error-red/10 border border-error-red/30 rounded-lg p-md mb-lg flex items-start gap-sm">
            <span class="material-symbols-outlined text-error-deep text-[20px]">warning</span>
            <div>
                <p class="text-xs font-bold text-error-deep">Balance D&eacute;s&eacute;quilibr&eacute;e &mdash; Cl&ocirc;ture Bloqu&eacute;e</p>
                <p class="text-[11px] text-error-deep mt-xs">Corrigez l'&eacute;cart de {{ number_format($this->periodeBalance['ecart'], 0, ',', ' ') }} FCFA sur <a href="{{ route('comptabilite.balance') }}" class="underline font-bold">Balance G&eacute;n&eacute;rale</a> avant de pouvoir cl&ocirc;turer ce mois.</p>
            </div>
        </div>
    @elseif($this->periodeDejaCloturee)
        <div class="bg-surface-zebra border border-outline-variant rounded-lg p-md mb-lg flex items-start gap-sm">
            <span class="material-symbols-outlined text-outline text-[20px]">lock</span>
            <div>
                <p class="text-xs font-bold text-brand-forest">Mois D&eacute;j&agrave; Cl&ocirc;tur&eacute;</p>
                <p class="text-[11px] text-outline mt-xs">Les &eacute;critures de cette p&eacute;riode sont verrouill&eacute;es en lecture seule.</p>
            </div>
        </div>
    @else
        <div class="bg-brand-emerald/10 border border-brand-emerald/30 rounded-lg p-md mb-lg flex items-start gap-sm">
            <span class="material-symbols-outlined text-brand-emerald text-[20px]">check_circle</span>
            <div>
                <p class="text-xs font-bold text-brand-emerald">Balance &Eacute;quilibr&eacute;e &mdash; Cl&ocirc;ture Autoris&eacute;e</p>
                <p class="text-[11px] text-outline mt-xs">Aucune anomalie d&eacute;tect&eacute;e pour ce mois. Vous pouvez proc&eacute;der &agrave; la cl&ocirc;ture p&eacute;riodique.</p>
            </div>
        </div>
    @endif

    @can('close-fiscal-year')
        <div class="flex justify-end mb-lg">
            <button type="button"
                    @disabled(! $this->periodeBalance['is_balanced'] || $this->periodeDejaCloturee)
                    x-on:click="$dispatch('open-modal', { name: 'modal-confirm-cloture-periodique' })"
                    class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm disabled:opacity-40 disabled:cursor-not-allowed">
                <span class="material-symbols-outlined text-[18px]">lock</span>Cl&ocirc;turer le Mois S&eacute;lectionn&eacute;
            </button>
        </div>
    @endcan

    <div class="bg-white border border-outline-variant rounded-lg overflow-hidden">
        <div class="px-md py-sm border-b border-outline-variant"><h3 class="text-sm font-bold text-brand-forest">Historique des Cl&ocirc;tures P&eacute;riodiques</h3></div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Mois</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date de Cl&ocirc;ture</th>
                        <th class="px-md py-sm text-center text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Action (Admin)</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->closures as $closure)
                        <tr class="rrow bg-white border-b border-outline-variant">
                            <td data-label="Mois" class="px-md py-sm text-xs font-semibold">{{ ucfirst(\Carbon\Carbon::createFromFormat('Y-m-d', $closure->period.'-01')->translatedFormat('F Y')) }}</td>
                            <td data-label="Date" class="px-md py-sm text-xs">{{ $closure->closed_at->format('d/m/Y') }}</td>
                            <td data-label="Statut" class="px-md py-sm text-center">
                                @if($closure->isLocked())
                                    <span class="text-[11px] font-bold px-sm py-0.5 rounded-full bg-error-red/10 text-error-deep">Cl&ocirc;tur&eacute;</span>
                                @else
                                    <span class="text-[11px] font-bold px-sm py-0.5 rounded-full bg-accent-yellow/20 text-brand-forest" title="D&eacute;cl&ocirc;tur&eacute; le {{ $closure->reopened_at->format('d/m/Y H:i') }}">D&eacute;cl&ocirc;tur&eacute;</span>
                                @endif
                            </td>
                            <td data-label="Action" class="px-md py-sm text-right">
                                @can('manage-modules')
                                    @if($closure->isLocked())
                                        <button type="button" wire:click="$set('closureAReouvrir', '{{ $closure->id }}')" x-on:click="$dispatch('open-modal', { name: 'modal-confirm-decloture' })" class="text-[11px] font-bold text-info-blue hover:underline">D&eacute;cl&ocirc;turer (exceptionnel)</button>
                                    @else
                                        <span class="text-[10px] text-outline italic">D&eacute;j&agrave; d&eacute;cl&ocirc;tur&eacute;</span>
                                    @endif
                                @else
                                    <span class="text-[10px] text-outline italic">R&eacute;serv&eacute; &agrave; l'Administrateur</span>
                                @endcan
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="4" class="px-md py-lg text-center text-outline">Aucun mois cl&ocirc;tur&eacute; &agrave; ce jour.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <p class="text-[11px] text-outline p-sm border-t border-outline-variant">Le bouton "D&eacute;cl&ocirc;turer" n'est visible et actif que pour le r&ocirc;le Administrateur &mdash; action journalis&eacute;e dans les Logs d'Audit.</p>
    </div>
@endif

@if($tab === 'annuelle')
    <div class="bg-white border border-outline-variant rounded-lg p-md mb-lg flex flex-col sm:flex-row sm:items-center gap-md">
        <div class="flex items-center gap-sm">
            <button type="button" wire:click="changeYear(-1)" dusk="year-prev" class="w-9 h-9 rounded-full border border-outline-variant flex items-center justify-center hover:bg-surface-zebra"><span class="material-symbols-outlined text-[18px]">chevron_left</span></button>
            <div class="text-center px-md">
                <p class="text-[10px] text-outline uppercase font-bold">Exercice Sélectionné</p>
                <p class="text-lg font-extrabold text-brand-forest">{{ $selectedYear }}</p>
            </div>
            <button type="button" wire:click="changeYear(1)" class="w-9 h-9 rounded-full border border-outline-variant flex items-center justify-center hover:bg-surface-zebra"><span class="material-symbols-outlined text-[18px]">chevron_right</span></button>
        </div>
        @if($this->fiscalYear)
            @if($this->fiscalYear->status === 'ouvert')
                <span class="inline-flex items-center gap-xs px-md py-2 rounded-full text-xs font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">
                    <span class="material-symbols-outlined text-[16px]">lock_open</span>EXERCICE {{ $selectedYear }} — OUVERT (Lecture / Écriture)
                </span>
            @else
                <span class="inline-flex items-center gap-xs px-md py-2 rounded-full text-xs font-bold border bg-error-bg text-error-deep border-error-deep/30">
                    <span class="material-symbols-outlined text-[16px]">lock</span>EXERCICE {{ $selectedYear }} — CLOS (Lecture Seule)
                </span>
            @endif
        @else
            <span class="inline-flex items-center gap-xs px-md py-2 rounded-full text-xs font-bold border bg-surface-zebra text-outline border-outline-variant">
                <span class="material-symbols-outlined text-[16px]">help</span>EXERCICE {{ $selectedYear }} — INEXISTANT
            </span>
        @endif
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-md mb-lg">
        <x-kpi-card label="Résultat Provisoire" icon="trending_up" color="emerald" :value="number_format($this->kpis['resultat'], 0, ',', ' ').' F'" />
        <x-kpi-card label="Comptes de Gestion à Solder" icon="receipt_long" color="blue" :value="$this->kpis['comptes_a_solder']" />
        @php($lettrage = $this->kpis['lettrage'])
        @if($lettrage['taux'] === null)
            <x-kpi-card label="Lettrage Bancaire" icon="account_balance" color="maize" :pending="true" pending-since="l'import d'un relevé bancaire (Comptabilité &gt; Rapprochement Bancaire)" />
        @else
            <x-kpi-card label="Lettrage Bancaire" icon="account_balance" color="maize"
                :value="number_format($lettrage['taux'], 0, ',', ' ').'%'"
                :caption="$lettrage['lettrees'].' / '.$lettrage['lignes'].' lignes lettrées'
                    .($lettrage['comptes_sans_releve'] > 0
                        ? ' — '.$lettrage['comptes_sans_releve'].' compte(s) sans relevé importé'
                        : '')" />
        @endif
    </div>

    @if($this->fiscalYear && $this->fiscalYear->status === 'ouvert')
        <div class="bg-white border border-outline-variant rounded-lg overflow-hidden">
            <div class="px-md py-sm border-b border-outline-variant"><h3 class="text-sm font-bold text-brand-forest">Assistant de Clôture d'Exercice ({{ $selectedYear }} → {{ (int)$selectedYear + 1 }})</h3></div>
            <div class="p-md space-y-sm">
                <div class="flex items-start gap-sm p-md rounded-lg border border-outline-variant">
                    <span class="w-7 h-7 rounded-full bg-brand-emerald text-white flex items-center justify-center text-xs font-bold flex-shrink-0">1</span>
                    <div class="flex-1">
                        <p class="text-sm font-bold text-brand-forest">Travaux d'Inventaire &amp; Régularisation</p>
                        <p class="text-xs text-outline mt-xs">Rapprochements bancaires (caisse/banque), amortissements, provisions, inventaire physique des stocks, charges/produits constatés d'avance (FNP/FAE) — à passer par le Journal Comptable avant de confirmer.</p>
                        @if($this->fiscalYear->step1_confirmed_at)
                            <p class="mt-sm text-xs font-bold text-brand-emerald flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">check_circle</span>Confirmé le {{ $this->fiscalYear->step1_confirmed_at->format('d/m/Y à H:i') }}</p>
                        @else
                            <button type="button" wire:click="confirmStep1" dusk="cloture-step1" class="mt-sm text-xs font-bold text-brand-emerald hover:underline">Marquer comme terminé</button>
                        @endif
                    </div>
                </div>
                <div class="flex items-start gap-sm p-md rounded-lg border border-outline-variant">
                    <span class="w-7 h-7 rounded-full bg-brand-emerald text-white flex items-center justify-center text-xs font-bold flex-shrink-0">2</span>
                    <div class="flex-1">
                        <p class="text-sm font-bold text-brand-forest">Solde des Comptes de Gestion (Classes 6 &amp; 7)</p>
                        <p class="text-xs text-outline mt-xs">Calcul du résultat net (Produits − Charges) et écriture de solde vers le compte 131 (Bénéfice) ou 139 (Perte).</p>
                        <button type="button" wire:click="soldeComptesGestion" dusk="cloture-step2" class="mt-sm text-xs font-bold text-brand-emerald hover:underline">Calculer et Solder</button>
                    </div>
                </div>
                <div class="flex items-start gap-sm p-md rounded-lg border border-outline-variant">
                    <span class="w-7 h-7 rounded-full bg-brand-emerald text-white flex items-center justify-center text-xs font-bold flex-shrink-0">3</span>
                    <div class="flex-1">
                        <p class="text-sm font-bold text-brand-forest">Génération des Écritures d'À-Nouveaux (RAN)</p>
                        <p class="text-xs text-outline mt-xs">Création de l'exercice {{ (int)$selectedYear + 1 }} et report des soldes de bilan (Classes 1 à 5) au 1er janvier {{ (int)$selectedYear + 1 }}. Verrouillage définitif de l'exercice {{ $selectedYear }}.</p>
                        <button type="button" x-on:click="$dispatch('open-modal', { name: 'modal-confirm-cloture' })" dusk="cloture-step3" class="mt-sm text-xs font-bold bg-error-red text-white px-md py-2 rounded-full">Clôturer l'Exercice {{ $selectedYear }}</button>
                    </div>
                </div>
            </div>
        </div>
    @elseif($this->fiscalYear)
        <div class="bg-white border border-outline-variant rounded-lg p-lg text-center">
            <span class="material-symbols-outlined text-outline-variant" style="font-size:48px;">lock</span>
            <p class="text-sm font-semibold text-on-surface mt-sm">Cet exercice est clôturé.</p>
            <p class="text-xs text-outline mt-xs">Consultable en lecture seule — clôturé le {{ $this->fiscalYear->closed_at?->format('d/m/Y à H:i') }}.</p>
        </div>
    @else
        <div class="bg-white border border-outline-variant rounded-lg p-lg text-center">
            <span class="material-symbols-outlined text-outline-variant" style="font-size:48px;">event_busy</span>
            <p class="text-sm font-semibold text-on-surface mt-sm">Aucun exercice {{ $selectedYear }} n'existe.</p>
        </div>
    @endif

@endif

    <x-modal name="modal-confirm-cloture-periodique" max-width="sm">
        <div class="text-center">
            <span class="material-symbols-outlined text-brand-emerald" style="font-size:48px;">lock</span>
            <h3 class="font-bold text-lg text-brand-forest mt-sm">Cl&ocirc;turer ce Mois ?</h3>
            <p class="text-xs text-outline mt-xs">Les &eacute;critures de ce mois seront verrouill&eacute;es en lecture seule. Contrairement &agrave; la cl&ocirc;ture annuelle, un d&eacute;blocage exceptionnel reste possible par un Administrateur.</p>
            <div class="flex justify-center gap-sm mt-lg">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-confirm-cloture-periodique' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="button" wire:click="cloturerPeriode" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Confirmer la Cl&ocirc;ture du Mois</button>
            </div>
        </div>
    </x-modal>

    <x-modal name="modal-confirm-decloture" max-width="sm">
        <div class="text-center">
            <span class="material-symbols-outlined text-accent-yellow" style="font-size:48px;">lock_open</span>
            <h3 class="font-bold text-lg text-brand-forest mt-sm">D&eacute;cl&ocirc;turer ce Mois ?</h3>
            <p class="text-xs text-outline mt-xs">Action exceptionnelle r&eacute;serv&eacute;e aux Administrateurs &mdash; sera journalis&eacute;e dans les Logs d'Audit avec votre identit&eacute; et un horodatage. Les &eacute;critures redeviendront modifiables.</p>
            <div class="flex justify-center gap-sm mt-lg">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-confirm-decloture' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="button" wire:click="decloturerPeriode(closureAReouvrir)" class="px-md py-sm rounded-lg bg-accent-yellow text-brand-forest text-sm font-bold">Confirmer la D&eacute;cl&ocirc;ture</button>
            </div>
        </div>
    </x-modal>

    <x-modal name="modal-confirm-cloture" max-width="sm">
        <div class="text-center">
            <span class="material-symbols-outlined text-error-deep" style="font-size:48px;">warning</span>
            <h3 class="font-bold text-lg text-error-deep mt-sm">Clôturer l'Exercice {{ $selectedYear }} ?</h3>
            <p class="text-xs text-outline mt-xs">Cette action verrouille définitivement toutes les écritures de {{ $selectedYear }} (lecture seule) et ouvre l'exercice {{ (int)$selectedYear + 1 }} avec les écritures de report à nouveau. Cette action est irréversible.</p>
            <div class="flex justify-center gap-sm mt-lg">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-confirm-cloture' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="button" wire:click="confirmCloture" dusk="cloture-confirm" class="px-md py-sm rounded-lg bg-error-red text-white text-sm font-bold hover:bg-red-800">Confirmer la Clôture</button>
            </div>
        </div>
    </x-modal>
</div>
