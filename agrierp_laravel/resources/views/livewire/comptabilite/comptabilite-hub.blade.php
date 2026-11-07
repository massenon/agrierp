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

    {{-- Les neuf cartes de la cible du client (07/11/2026), dans CET ordre, textes exacts. Le poste les reprend
         (`PageComptable` : libellé + description) ; `ComptabiliteHubCartesTest` et `comptabilite_hub_cartes_test.dart` les gardent. --}}
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
        <a wire:navigate href="{{ route('comptabilite.plan') }}" data-carte-compta class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">menu_book</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Plan Comptable</p>
                <p class="text-[11px] text-outline">Comptes SYSCOHADA (Classes 1 à 7)</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.journal') }}" data-carte-compta class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">account_balance</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Journal Comptable</p>
                <p class="text-[11px] text-outline">Écritures Débit/Crédit, saisie manuelle</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.grand-livre') }}" data-carte-compta class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">import_contacts</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Grand Livre</p>
                <p class="text-[11px] text-outline">Écritures par compte, solde progressif</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.balance') }}" data-carte-compta class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">balance</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Balance Générale</p>
                <p class="text-[11px] text-outline">Soldes de tous les comptes utilisés</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.etats-financiers') }}" data-carte-compta class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">description</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">États Financiers</p>
                <p class="text-[11px] text-outline">Bilan, Résultat, Flux de Trésorerie, Notes Annexes</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.cloture') }}" data-carte-compta class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">event_repeat</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Clôture Périodique &amp; Annuelle</p>
                <p class="text-[11px] text-outline">Clôture mensuelle, bascule d'exercice, report à nouveau</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.analytique') }}" data-carte-compta class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">insights</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Comptabilité Analytique</p>
                <p class="text-[11px] text-outline">Marges réelles par filière (Cuniculture, Aviculture, Porciculture)</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.declaration-tva') }}" data-carte-compta class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">receipt_long</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Déclaration TVA</p>
                <p class="text-[11px] text-outline">TVA Collectée / Déductible, taux 18% ou exonéré</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.rapprochement') }}" data-carte-compta class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">sync_alt</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Rapprochement Bancaire</p>
                <p class="text-[11px] text-outline">Pointage Grand Livre / Relevé Banque et Mobile Money</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
    </div>

    {{-- Pages réelles qui n'ont pas d'autre accès et ne figurent pas dans la liste du client : conservées ici, après les neuf. --}}
    <h3 class="text-xs font-bold text-outline uppercase tracking-wide mt-lg mb-sm">Autres états</h3>
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-md" data-autres-etats>
        <a wire:navigate href="{{ route('comptabilite.bilan') }}" data-carte-compta class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">account_balance_wallet</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Bilan de l'Entreprise</p>
                <p class="text-[11px] text-outline">Actif / Passif, équilibre comptable</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.immobilisations') }}" data-carte-compta class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">domain</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Immobilisations</p>
                <p class="text-[11px] text-outline">Registre des biens, amortissement lineaire et dotation</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
        <a wire:navigate href="{{ route('comptabilite.balance-agee') }}" data-carte-compta class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
            <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-brand-emerald text-[24px]">schedule</span></div>
            <div class="min-w-0 flex-1">
                <p class="text-sm font-bold text-brand-forest">Balance Âgée</p>
                <p class="text-[11px] text-outline">Encours clients et fournisseurs par ancienneté de retard</p>
            </div>
            <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
        </a>
    </div>
</div>
