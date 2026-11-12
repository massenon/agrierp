<div>
    <div class="border-b border-outline-variant pb-md mb-lg flex flex-col sm:flex-row sm:items-center sm:justify-between gap-sm">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">event_repeat</span>{{ __('comptabilite.cloture_titre') }}
            </h2>
            <p class="text-xs text-outline mt-xs">{{ __('comptabilite.cloture_sous_titre') }}</p>
        </div>
        <button type="button" wire:click="exportClotureExercicePdf" wire:loading.attr="disabled" wire:target="exportClotureExercicePdf" class="flex items-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>{{ __('comptabilite.cloture_exporter_pdf') }}
        </button>
    </div>

    <div class="flex items-center gap-xs border-b border-outline-variant mb-md overflow-x-auto">
        <button type="button" wire:click="$set('tab', 'periodique')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'periodique' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">{{ __('comptabilite.cloture_tab_periodique') }}</button>
        <button type="button" wire:click="$set('tab', 'annuelle')" dusk="tab-annuelle" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'annuelle' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">{{ __('comptabilite.cloture_tab_annuelle') }}</button>
    </div>

@if($tab === 'periodique')
    <p class="text-xs text-outline mb-md">{{ __('comptabilite.cloture_periodique_desc') }}</p>

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-lg flex flex-wrap items-center gap-sm">
        <label for="periodique-mois-select" class="text-[10px] text-brand-forest font-bold uppercase">{{ __('comptabilite.cloture_mois_label') }}</label>
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
                <p class="text-xs font-bold text-error-deep">{{ __('comptabilite.cloture_balance_ko_titre') }}</p>
                <p class="text-[11px] text-error-deep mt-xs">{{ __('comptabilite.cloture_balance_ko_msg', ['ecart' => number_format(\$this->periodeBalance['ecart'], 0, ',', ' ')]) }} <a wire:navigate href="{{ route('comptabilite.balance') }}" class="underline font-bold">{{ __('comptabilite.cloture_balance_ko_lien') }}</a>{{ __('comptabilite.cloture_balance_ko_msg_suite') }}</p>
            </div>
        </div>
    @elseif($this->periodeDejaCloturee)
        <div class="bg-surface-zebra border border-outline-variant rounded-lg p-md mb-lg flex items-start gap-sm">
            <span class="material-symbols-outlined text-outline text-[20px]">lock</span>
            <div>
                <p class="text-xs font-bold text-brand-forest">{{ __('comptabilite.cloture_deja_cloture_titre') }}</p>
                <p class="text-[11px] text-outline mt-xs">{{ __('comptabilite.cloture_deja_cloture_msg') }}</p>
            </div>
        </div>
    @else
        <div class="bg-brand-emerald/10 border border-brand-emerald/30 rounded-lg p-md mb-lg flex items-start gap-sm">
            <span class="material-symbols-outlined text-brand-emerald text-[20px]">check_circle</span>
            <div>
                <p class="text-xs font-bold text-brand-emerald">{{ __('comptabilite.cloture_ok_titre') }}</p>
                <p class="text-[11px] text-outline mt-xs">{{ __('comptabilite.cloture_ok_msg') }}</p>
            </div>
        </div>
    @endif

    @can('close-fiscal-year')
        <div class="flex justify-end mb-lg">
            <button type="button"
                    @disabled(! $this->periodeBalance['is_balanced'] || $this->periodeDejaCloturee)
                    x-on:click="$dispatch('open-modal', { name: 'modal-confirm-cloture-periodique' })"
                    class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm disabled:opacity-40 disabled:cursor-not-allowed">
                <span class="material-symbols-outlined text-[18px]">lock</span>{{ __('comptabilite.cloture_btn_cloturer_mois') }}
            </button>
        </div>
    @endcan

    <div class="bg-white border border-outline-variant rounded-lg overflow-hidden">
        <div class="px-md py-sm border-b border-outline-variant"><h3 class="text-sm font-bold text-brand-forest">{{ __('comptabilite.cloture_historique_titre') }}</h3></div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('comptabilite.cloture_col_mois') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('comptabilite.cloture_col_date') }}</th>
                        <th class="px-md py-sm text-center text-[10px] text-outline font-bold uppercase">{{ __('comptabilite.cloture_col_statut') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('comptabilite.cloture_col_action') }}</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->closures as $closure)
                        <tr class="rrow bg-white border-b border-outline-variant">
                            <td data-label="Mois" class="px-md py-sm text-xs font-semibold">{{ ucfirst(\Carbon\Carbon::createFromFormat('Y-m-d', $closure->period.'-01')->translatedFormat('F Y')) }}</td>
                            <td data-label="Date" class="px-md py-sm text-xs">{{ $closure->closed_at->format('d/m/Y') }}</td>
                            <td data-label="Statut" class="px-md py-sm text-center">
                                @if($closure->isLocked())
                                    <span class="text-[11px] font-bold px-sm py-0.5 rounded-full bg-error-red/10 text-error-deep">{{ __('comptabilite.cloture_statut_cloture') }}</span>
                                @else
                                    <span class="text-[11px] font-bold px-sm py-0.5 rounded-full bg-accent-yellow/20 text-brand-forest" title="D&eacute;cl&ocirc;tur&eacute; le {{ $closure->reopened_at->format('d/m/Y H:i') }}">{{ __('comptabilite.cloture_statut_decloture') }}</span>
                                @endif
                            </td>
                            <td data-label="Action" class="px-md py-sm text-right">
                                @can('manage-modules')
                                    @if($closure->isLocked())
                                        <button type="button" wire:click="$set('closureAReouvrir', '{{ $closure->id }}')" x-on:click="$dispatch('open-modal', { name: 'modal-confirm-decloture' })" class="text-[11px] font-bold text-info-blue hover:underline">{{ __('comptabilite.cloture_btn_decloturer') }}</button>
                                    @else
                                        <span class="text-[10px] text-outline italic">{{ __('comptabilite.cloture_deja_decloture') }}</span>
                                    @endif
                                @else
                                    <span class="text-[10px] text-outline italic">{{ __('comptabilite.cloture_reserve_admin') }}</span>
                                @endcan
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="4" class="px-md py-lg text-center text-outline">{{ __('comptabilite.cloture_vide') }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <p class="text-[11px] text-outline p-sm border-t border-outline-variant">{{ __('comptabilite.cloture_note_decloturer') }}</p>
    </div>
@endif

@if($tab === 'annuelle')
    <div class="bg-white border border-outline-variant rounded-lg p-md mb-lg flex flex-col sm:flex-row sm:items-center gap-md">
        <div class="flex items-center gap-sm">
            <button type="button" wire:click="changeYear(-1)" dusk="year-prev" class="w-9 h-9 rounded-full border border-outline-variant flex items-center justify-center hover:bg-surface-zebra"><span class="material-symbols-outlined text-[18px]">chevron_left</span></button>
            <div class="text-center px-md">
                <p class="text-[10px] text-outline uppercase font-bold">{{ __('comptabilite.cloture_exercice_selectionne') }}</p>
                <p class="text-lg font-extrabold text-brand-forest">{{ $selectedYear }}</p>
            </div>
            <button type="button" wire:click="changeYear(1)" class="w-9 h-9 rounded-full border border-outline-variant flex items-center justify-center hover:bg-surface-zebra"><span class="material-symbols-outlined text-[18px]">chevron_right</span></button>
        </div>
        @if($this->fiscalYear)
            @if($this->fiscalYear->status === 'ouvert')
                <span class="inline-flex items-center gap-xs px-md py-2 rounded-full text-xs font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">
                    <span class="material-symbols-outlined text-[16px]">lock_open</span>{{ __('comptabilite.cloture_exercice_ouvert', ['year' => $selectedYear]) }}
                </span>
                {{-- Ticket EX3 (EF2) — ouverture de N+1 sans attendre la clôture de N, à partir du 1er décembre. --}}
                @can('close-fiscal-year')
                    @if($this->peutOuvrirSuivant)
                        <button type="button" wire:click="ouvrirExerciceSuivant" wire:loading.attr="disabled" wire:target="ouvrirExerciceSuivant" dusk="ouvrir-exercice-suivant"
                            class="inline-flex items-center gap-xs px-md py-2 rounded-full text-xs font-bold bg-brand-emerald text-white hover:bg-brand-forest disabled:opacity-50">
                            <span class="material-symbols-outlined text-[16px]">calendar_month</span>{{ __('comptabilite.cloture_ouvrir_suivant', ['year' => (int)$selectedYear + 1]) }}
                        </button>
                    @endif
                @endcan
            @else
                <span class="inline-flex items-center gap-xs px-md py-2 rounded-full text-xs font-bold border bg-error-bg text-error-deep border-error-deep/30">
                    <span class="material-symbols-outlined text-[16px]">lock</span>{{ __('comptabilite.cloture_exercice_clos', ['year' => $selectedYear]) }}
                </span>
                {{-- Ticket 15.53 — réouverture exceptionnelle, administrateur seulement. --}}
                @can('manage-modules')
                    <button type="button" x-on:click="$dispatch('open-modal', { name: 'modal-confirm-reouverture' })" dusk="rouvrir-exercice"
                        class="inline-flex items-center gap-xs px-md py-2 rounded-full text-xs font-bold bg-accent-yellow text-brand-forest">
                        <span class="material-symbols-outlined text-[16px]">lock_open</span>{{ __('comptabilite.cloture_rouvrir', ['year' => $selectedYear]) }}
                    </button>
                @endcan
            @endif
        @else
            <span class="inline-flex items-center gap-xs px-md py-2 rounded-full text-xs font-bold border bg-surface-zebra text-outline border-outline-variant">
                <span class="material-symbols-outlined text-[16px]">help</span>{{ __('comptabilite.cloture_exercice_inexistant', ['year' => $selectedYear]) }}
            </span>
        @endif
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-md mb-lg">
        <x-kpi-card :label="__('comptabilite.cloture_kpi_resultat')" icon="trending_up" color="emerald" :value="number_format($this->kpis['resultat'], 0, ',', ' ').' F'" />
        <x-kpi-card :label="__('comptabilite.cloture_kpi_comptes_solder')" icon="receipt_long" color="blue" :value="$this->kpis['comptes_a_solder']" />
        @php($lettrage = $this->kpis['lettrage'])
        @if($lettrage['taux'] === null)
            <x-kpi-card :label="__('comptabilite.cloture_kpi_lettrage')" icon="account_balance" color="maize" :pending="true" pending-since="l'import d'un relevé bancaire (Comptabilité &gt; Rapprochement Bancaire)" />
        @else
            <x-kpi-card :label="__('comptabilite.cloture_kpi_lettrage')" icon="account_balance" color="maize"
                :value="number_format($lettrage['taux'], 0, ',', ' ').'%'"
                :caption="$lettrage['lettrees'].' / '.$lettrage['lignes'].' lignes lettrées'
                    .($lettrage['comptes_sans_releve'] > 0
                        ? ' — '.$lettrage['comptes_sans_releve'].' compte(s) sans relevé importé'
                        : '')" />
        @endif
    </div>

    @if($this->fiscalYear && $this->fiscalYear->status === 'ouvert')
        <div class="bg-white border border-outline-variant rounded-lg overflow-hidden">
            <div class="px-md py-sm border-b border-outline-variant"><h3 class="text-sm font-bold text-brand-forest">{{ __('comptabilite.cloture_assistant_titre') }} ({{ $selectedYear }} → {{ (int)$selectedYear + 1 }})</h3></div>
            <div class="p-md space-y-sm">
                <div class="flex items-start gap-sm p-md rounded-lg border border-outline-variant">
                    <span class="w-7 h-7 rounded-full bg-brand-emerald text-white flex items-center justify-center text-xs font-bold flex-shrink-0">1</span>
                    <div class="flex-1">
                        <p class="text-sm font-bold text-brand-forest">{{ __('comptabilite.cloture_step1_titre') }}</p>
                        <p class="text-xs text-outline mt-xs">{{ __('comptabilite.cloture_step1_desc') }}</p>
                        @if($this->fiscalYear->step1_confirmed_at)
                            <p class="mt-sm text-xs font-bold text-brand-emerald flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">check_circle</span>Confirmé le {{ $this->fiscalYear->step1_confirmed_at->format('d/m/Y à H:i') }}</p>
                        @else
                            <button type="button" wire:click="confirmStep1" dusk="cloture-step1" class="mt-sm text-xs font-bold text-brand-emerald hover:underline">{{ __('comptabilite.cloture_step1_btn') }}</button>
                        @endif
                    </div>
                </div>
                <div class="flex items-start gap-sm p-md rounded-lg border border-outline-variant">
                    <span class="w-7 h-7 rounded-full bg-brand-emerald text-white flex items-center justify-center text-xs font-bold flex-shrink-0">2</span>
                    <div class="flex-1">
                        <p class="text-sm font-bold text-brand-forest">{{ __('comptabilite.cloture_step2_titre') }}</p>
                        <p class="text-xs text-outline mt-xs">{{ __('comptabilite.cloture_step2_desc') }}</p>
                        <button type="button" wire:click="soldeComptesGestion" dusk="cloture-step2" class="mt-sm text-xs font-bold text-brand-emerald hover:underline">{{ __('comptabilite.cloture_step2_btn') }}</button>
                    </div>
                </div>
                <div class="flex items-start gap-sm p-md rounded-lg border border-outline-variant">
                    <span class="w-7 h-7 rounded-full bg-brand-emerald text-white flex items-center justify-center text-xs font-bold flex-shrink-0">3</span>
                    <div class="flex-1">
                        <p class="text-sm font-bold text-brand-forest">{{ __('comptabilite.cloture_step3_titre') }}</p>
                        <p class="text-xs text-outline mt-xs">{{ __('comptabilite.cloture_step3_desc', ['year' => $selectedYear, 'year1' => (int)$selectedYear + 1]) }}</p>
                        {{-- Ticket EX4 (EF4) — grisé avec son motif tant qu'une garde refuse ; le serveur rejuge à l'appel. --}}
                        @php($motifCloture = $this->motifRefusCloture)
                        <button type="button" x-on:click="$dispatch('open-modal', { name: 'modal-confirm-cloture' })" dusk="cloture-step3" @disabled($motifCloture !== null) @if($motifCloture) title="{{ $motifCloture }}" @endif class="mt-sm text-xs font-bold bg-error-red text-white px-md py-2 rounded-full disabled:opacity-50 disabled:cursor-not-allowed">{{ __('comptabilite.cloture_step3_btn', ['year' => $selectedYear]) }}</button>
                        @if($motifCloture)
                            <p class="mt-xs text-xs text-error-deep flex items-start gap-xs" dusk="cloture-step3-motif"><span class="material-symbols-outlined text-[16px]">info</span>{{ $motifCloture }}</p>
                        @endif
                    </div>
                </div>
            </div>
        </div>
    @elseif($this->fiscalYear)
        <div class="bg-white border border-outline-variant rounded-lg p-lg text-center">
            <span class="material-symbols-outlined text-outline-variant" style="font-size:48px;">lock</span>
            <p class="text-sm font-semibold text-on-surface mt-sm">{{ __('comptabilite.cloture_exo_clos_titre') }}</p>
            <p class="text-xs text-outline mt-xs">{{ __('comptabilite.cloture_exo_clos_msg') }} {{ $this->fiscalYear->closed_at?->format('d/m/Y à H:i') }}.</p>
        </div>
    @else
        <div class="bg-white border border-outline-variant rounded-lg p-lg text-center">
            <span class="material-symbols-outlined text-outline-variant" style="font-size:48px;">event_busy</span>
            <p class="text-sm font-semibold text-on-surface mt-sm">{{ __('comptabilite.cloture_exo_absent_titre', ['year' => $selectedYear]) }}</p>
        </div>
    @endif

@endif

    <x-modal name="modal-confirm-cloture-periodique" max-width="sm">
        <div class="text-center">
            <span class="material-symbols-outlined text-brand-emerald" style="font-size:48px;">lock</span>
            <h3 class="font-bold text-lg text-brand-forest mt-sm">{{ __('comptabilite.cloture_modal_periodo_titre') }}</h3>
            <p class="text-xs text-outline mt-xs">{{ __('comptabilite.cloture_modal_periodo_msg') }}</p>
            <div class="flex justify-center gap-sm mt-lg">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-confirm-cloture-periodique' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('comptabilite.annuler') }}</button>
                <button type="button" wire:click="cloturerPeriode" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ __('comptabilite.cloture_modal_periodo_btn') }}</button>
            </div>
        </div>
    </x-modal>

    <x-modal name="modal-confirm-decloture" max-width="sm">
        <div class="text-center">
            <span class="material-symbols-outlined text-accent-yellow" style="font-size:48px;">lock_open</span>
            <h3 class="font-bold text-lg text-brand-forest mt-sm">{{ __('comptabilite.cloture_modal_decloture_titre') }}</h3>
            <p class="text-xs text-outline mt-xs">{{ __('comptabilite.cloture_modal_decloture_msg') }}</p>
            <div class="flex justify-center gap-sm mt-lg">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-confirm-decloture' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('comptabilite.annuler') }}</button>
                <button type="button" wire:click="decloturerPeriode(closureAReouvrir)" class="px-md py-sm rounded-lg bg-accent-yellow text-brand-forest text-sm font-bold">{{ __('comptabilite.cloture_modal_decloture_btn') }}</button>
            </div>
        </div>
    </x-modal>

    <x-modal name="modal-confirm-reouverture" max-width="sm">
        <div class="text-center">
            <span class="material-symbols-outlined text-accent-yellow" style="font-size:48px;">lock_open</span>
            <h3 class="font-bold text-lg text-brand-forest mt-sm">{{ __('comptabilite.cloture_modal_reouv_titre', ['year' => $selectedYear]) }}</h3>
            <p class="text-xs text-outline mt-xs">{{ __('comptabilite.cloture_modal_reouv_msg', ['year' => $selectedYear, 'year1' => (int)$selectedYear + 1]) }}</p>
            <div class="flex justify-center gap-sm mt-lg">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-confirm-reouverture' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('comptabilite.annuler') }}</button>
                <button type="button" wire:click="rouvrirExercice" dusk="reouverture-confirm" class="px-md py-sm rounded-lg bg-accent-yellow text-brand-forest text-sm font-bold">{{ __('comptabilite.cloture_modal_reouv_btn') }}</button>
            </div>
        </div>
    </x-modal>

    <x-modal name="modal-confirm-cloture" max-width="sm">
        <div class="text-center">
            <span class="material-symbols-outlined text-error-deep" style="font-size:48px;">warning</span>
            <h3 class="font-bold text-lg text-error-deep mt-sm">{{ __('comptabilite.cloture_modal_cloture_titre', ['year' => $selectedYear]) }}</h3>
            <p class="text-xs text-outline mt-xs">{{ __('comptabilite.cloture_modal_cloture_msg', ['year' => $selectedYear, 'year1' => (int)$selectedYear + 1]) }}</p>
            <div class="flex justify-center gap-sm mt-lg">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-confirm-cloture' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('comptabilite.annuler') }}</button>
                <button type="button" wire:click="confirmCloture" dusk="cloture-confirm" class="px-md py-sm rounded-lg bg-error-red text-white text-sm font-bold hover:bg-red-800">{{ __('comptabilite.cloture_modal_cloture_btn') }}</button>
            </div>
        </div>
    </x-modal>
</div>
