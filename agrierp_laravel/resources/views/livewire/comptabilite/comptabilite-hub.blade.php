<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">account_balance</span>Comptabilité
        </h2>
        <p class="text-xs text-outline mt-xs">Pilotage financier SYSCOHADA — plan comptable, journal, bilan, clôture et analytique.</p>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md mb-lg">
        <x-kpi-card label="Total Actif (Bilan)" icon="account_balance_wallet" color="emerald" :value="number_format($this->kpis['total_actif'], 0, ',', ' ').' FCFA'" />
        <x-kpi-card label="Recettes du Mois" icon="payments" color="blue" :value="number_format($this->kpis['recettes_mois'], 0, ',', ' ').' FCFA'" />
        <x-kpi-card label="Marge Nette (Analytique)" icon="percent" color="maize" :value="$this->kpis['marge_nette'] !== null ? $this->kpis['marge_nette'].' %' : '—'" />
        <x-kpi-card label="Trésorerie Disponible" icon="account_balance" color="red" :value="number_format($this->kpis['tresorerie'], 0, ',', ' ').' FCFA'" />
    </div>

    <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
        <a href="{{ route('comptabilite.plan') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">menu_book</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Plan Comptable</p>
                <p class="text-[11px] text-outline">Comptes SYSCOHADA (Classes 1 à 8)</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a href="{{ route('comptabilite.journal') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">account_balance</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Journal Comptable</p>
                <p class="text-[11px] text-outline">Écritures Débit/Crédit, saisie manuelle</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a href="{{ route('comptabilite.grand-livre') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">import_contacts</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Grand Livre</p>
                <p class="text-[11px] text-outline">Écritures par compte, solde progressif</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a href="{{ route('comptabilite.balance') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">balance</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Balance Générale</p>
                <p class="text-[11px] text-outline">Soldes de tous les comptes utilisés</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a href="{{ route('comptabilite.etats-financiers') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">description</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">États Financiers</p>
                <p class="text-[11px] text-outline">Bilan, Résultat, Flux de Trésorerie, Notes Annexes</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>

        <a href="{{ route('comptabilite.bilan') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">account_balance_wallet</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Bilan de l'Entreprise</p>
                <p class="text-[11px] text-outline">Actif / Passif, équilibre comptable</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a href="{{ route('comptabilite.immobilisations') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">domain</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Immobilisations</p>
                <p class="text-[11px] text-outline">Registre des biens, amortissement lineaire et dotation</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>

        <a href="{{ route('comptabilite.cloture') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">event_repeat</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Clôture d'Exercice</p>
                <p class="text-[11px] text-outline">Bascule d'exercice fiscal, report à nouveau</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a href="{{ route('comptabilite.declaration-tva') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">receipt_long</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Declaration TVA</p>
                <p class="text-[11px] text-outline">TVA collectee et deductible, echeance DGI</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>

        <a href="{{ route('comptabilite.rapprochement') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">sync_alt</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Rapprochement Bancaire</p>
                <p class="text-[11px] text-outline">Pointage Grand Livre / releve importe</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
                <a href="{{ route('comptabilite.analytique') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all sm:col-span-2">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">insights</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Comptabilité Analytique</p>
                <p class="text-[11px] text-outline">Marges réelles par filière (Cuniculture, Aviculture, Porciculture...)</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a href="{{ route('comptabilite.balance-agee') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">schedule</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Balance Âgée</p>
                <p class="text-[11px] text-outline">Encours clients et fournisseurs par ancienneté de retard</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
    </div>
</div>
