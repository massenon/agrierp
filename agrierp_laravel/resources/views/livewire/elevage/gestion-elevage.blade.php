<div>
    <div class="mb-md">
        <h2 class="text-lg lg:text-xl font-bold flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald">pets</span>{{ __('elevage.titre_gestion_elevage') }}</h2>
        <p class="text-xs text-outline mt-xs">{{ __('elevage.desc_gestion_elevage') }}</p>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-sm lg:gap-md mb-lg">
        <x-kpi-card :label="__('elevage.kpi_effectif_total_vivant')" icon="pets" color="emerald" :value="number_format($this->effectifTotal, 0, ',', ' ')" :caption="__('elevage.caption_effectif_total')" />
        <x-kpi-card :label="__('elevage.kpi_bandes_actives')" icon="layers" color="maize" :value="$this->bandesActives" :caption="__('elevage.caption_bandes_actives')" />
        <x-kpi-card :label="__('elevage.kpi_alertes_stock_aliment')" icon="warning" color="red" :pending="true" pending-since="Sprint 6 (Stocks)" />
        <x-kpi-card :label="__('elevage.kpi_taux_mortalite_mois')"
            icon="monitor_heart" color="blue"
            :value="$this->tauxMortaliteMois !== null ? number_format($this->tauxMortaliteMois, 2, ',', ' ').' %' : '—'"
            :caption="$this->tauxMortaliteMois !== null ? 'Seuil normal < 5%' : 'Aucune fiche journalière saisie ce mois-ci'" />
    </div>

    <h3 class="text-xs font-bold text-brand-forest uppercase tracking-wider mb-sm">{{ __('elevage.titre_registres_espece') }}</h3>
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-md mb-lg">
        <x-nav-card href="/gestion-bandes" icon="layers" title="Bandes & Sujets" :description="$this->bandesActives.' bande(s) active(s) — création, numérotation individuelle'" />
        <x-nav-card href="/fiche-lapins" icon="cruelty_free" :title="__('elevage.nav_fiches_lapins_title')" description="Suivi mensuel du cheptel — Cuniculture" />
        <x-nav-card href="/fiche-volailles-pondeuses" icon="egg" :title="__('elevage.nav_fiches_pondeuses_title')" description="Suivi quotidien de la ponte et récolte d'œufs" />
        <x-nav-card href="/fiche-volailles-reproducteurs" icon="pets" :title="__('elevage.nav_fiches_volailles_title')" description="Reproducteurs, poussins, Goliath/Chair" />
        <x-nav-card href="/fiche-porcs" icon="pets" :title="__('elevage.nav_fiches_porcs_title')" description="Suivi journalier — Porciculture" />
        @if($this->helicoEnabled)
            <x-nav-card href="{{ route('elevage.fiche-escargots') }}" icon="bug_report" :title="__('elevage.nav_fiches_escargots_title')" description="Héliciculture — suivi mensuel du cheptel" />
        @else
            <a wire:navigate href="{{ route('elevage.fiche-escargots') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
                <div class="w-12 h-12 rounded-lg bg-outline-variant/20 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-outline text-[24px]">bug_report</span></div>
                <div class="min-w-0 flex-1">
                    <p class="text-sm font-bold text-brand-forest">{{ __('elevage.nav_fiches_escargots_title') }}</p>
                    <p class="text-[11px] text-outline">{{ __('elevage.nav_helico_desactive') }}</p>
                </div>
                <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
            </a>
        @endif
    </div>

    <h3 class="text-xs font-bold text-brand-forest uppercase tracking-wider mb-sm">{{ __('elevage.titre_acces_rapides') }}</h3>
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-md mb-lg">
        <x-nav-card href="/suivi-reproduction" icon="favorite" :title="__('elevage.nav_suivi_reproduction_title')" description="Saillies, palpations, mises bas, sevrages" />
        <x-nav-card href="/soins-vaccins-hub" icon="vaccines" :title="__('elevage.nav_soins_vaccins_title')" description="Registre vétérinaire, calendrier, rémanence" />
        <x-nav-card href="/elevage-dashboard" icon="dashboard" :title="__('elevage.nav_dashboard_title')" description="GMQ, rentabilité, alertes" />
        <x-nav-card href="/transferts-bandes" icon="swap_horiz" :title="__('elevage.nav_transferts_title')" description="Portées, sevrés, regroupements ; rattachement à la bande d'origine" />
    </div>
</div>
