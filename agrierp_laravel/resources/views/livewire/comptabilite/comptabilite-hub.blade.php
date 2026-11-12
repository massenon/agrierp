<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">account_balance</span>{{ __('comptabilite.titre_page') }}
        </h2>
        <p class="text-xs text-outline mt-xs">{{ __('comptabilite.sous_titre_page') }}</p>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md mb-lg">
        <x-kpi-card :label="__('comptabilite.kpi_total_actif')" icon="account_balance_wallet" color="emerald" :value="number_format($this->kpis['total_actif'], 0, ',', ' ').' FCFA'" />
        <x-kpi-card :label="__('comptabilite.kpi_recettes_mois')" icon="payments" color="blue" :value="number_format($this->kpis['recettes_mois'], 0, ',', ' ').' FCFA'" />
        <x-kpi-card :label="__('comptabilite.kpi_marge_nette')" icon="percent" color="maize" :value="$this->kpis['marge_nette'] !== null ? $this->kpis['marge_nette'].' %' : '—'" />
        <x-kpi-card :label="__('comptabilite.kpi_tresorerie')" icon="account_balance" color="red" :value="number_format($this->kpis['tresorerie'], 0, ',', ' ').' FCFA'" />
    </div>

    {{-- Une SEULE grille de DOUZE cartes (décision du client, 07/11/2026) : les neuf de sa liste, dans cet ordre, puis les trois
         pages réelles qui n'ont pas d'autre accès. Le poste les reprend à l'identique (`PageComptable` : libellé, description,
         icône) ; `ComptabiliteHubCartesTest` et `comptabilite_hub_cartes_test.dart` les gardent. --}}
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
        <a wire:navigate href="{{ route('comptabilite.plan') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">menu_book</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">{{ __('comptabilite.nav_plan_titre') }}</p>
                <p class="text-[11px] text-outline">{{ __('comptabilite.nav_plan_desc') }}</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.journal') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">account_balance</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">{{ __('comptabilite.nav_journal_titre') }}</p>
                <p class="text-[11px] text-outline">{{ __('comptabilite.nav_journal_desc') }}</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.grand-livre') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">import_contacts</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">{{ __('comptabilite.nav_grand_livre_titre') }}</p>
                <p class="text-[11px] text-outline">{{ __('comptabilite.nav_grand_livre_desc') }}</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.balance') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">balance</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">{{ __('comptabilite.nav_balance_titre') }}</p>
                <p class="text-[11px] text-outline">{{ __('comptabilite.nav_balance_desc') }}</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.etats-financiers') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">description</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">{{ __('comptabilite.nav_etats_titre') }}</p>
                <p class="text-[11px] text-outline">{{ __('comptabilite.nav_etats_desc') }}</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.cloture') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">event_repeat</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">{{ __('comptabilite.nav_cloture_titre') }}</p>
                <p class="text-[11px] text-outline">{{ __('comptabilite.nav_cloture_desc') }}</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.analytique') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">insights</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">{{ __('comptabilite.nav_analytique_titre') }}</p>
                <p class="text-[11px] text-outline">{{ __('comptabilite.nav_analytique_desc') }}</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.declaration-tva') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">receipt_long</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">{{ __('comptabilite.nav_tva_titre') }}</p>
                <p class="text-[11px] text-outline">{{ __('comptabilite.nav_tva_desc') }}</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.rapprochement') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">sync_alt</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">{{ __('comptabilite.nav_rappro_titre') }}</p>
                <p class="text-[11px] text-outline">{{ __('comptabilite.nav_rappro_desc') }}</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.bilan') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">account_balance</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">{{ __('comptabilite.nav_bilan_titre') }}</p>
                <p class="text-[11px] text-outline">{{ __('comptabilite.nav_bilan_desc') }}</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.immobilisations') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">domain</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">{{ __('comptabilite.nav_immo_titre') }}</p>
                <p class="text-[11px] text-outline">{{ __('comptabilite.nav_immo_desc') }}</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.balance-agee') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">schedule</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">{{ __('comptabilite.nav_balance_agee_titre') }}</p>
                <p class="text-[11px] text-outline">{{ __('comptabilite.nav_balance_agee_desc') }}</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
    </div>
</div>
