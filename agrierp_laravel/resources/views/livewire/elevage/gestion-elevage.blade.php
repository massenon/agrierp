<div>
    <div class="mb-md">
        <h2 class="text-lg lg:text-xl font-bold flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald">pets</span>Gestion Élevage</h2>
        <p class="text-xs text-outline mt-xs">Vue d'ensemble du cheptel et accès rapide aux registres de chaque espèce.</p>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-sm lg:gap-md mb-lg">
        <x-kpi-card label="Effectif Total Vivant" icon="pets" color="emerald" :value="number_format($this->effectifTotal, 0, ',', ' ')" caption="Cumul de tous les animaux vivants enregistrés" />
        <x-kpi-card label="Bandes Actives" icon="layers" color="maize" :value="$this->bandesActives" caption="Lots au statut « Actif », toutes espèces" />
        <x-kpi-card label="Alertes Stock Aliment" icon="warning" color="red" :pending="true" pending-since="Sprint 6 (Stocks)" />
        <x-kpi-card label="Taux Mortalité (mois)"
            icon="monitor_heart" color="blue"
            :value="$this->tauxMortaliteMois !== null ? number_format($this->tauxMortaliteMois, 2, ',', ' ').' %' : '—'"
            :caption="$this->tauxMortaliteMois !== null ? 'Seuil normal < 5%' : 'Aucune fiche journalière saisie ce mois-ci'" />
    </div>

    <h3 class="text-xs font-bold text-brand-forest uppercase tracking-wider mb-sm">Registres par Espèce</h3>
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-md mb-lg">
        <x-nav-card href="/gestion-bandes" icon="layers" title="Bandes & Sujets" :description="$this->bandesActives.' bande(s) active(s) — création, numérotation individuelle'" />
        <x-nav-card href="/fiche-lapins" icon="cruelty_free" title="Fiches Lapins" description="Suivi mensuel du cheptel — Cuniculture" />
        <x-nav-card href="/fiche-volailles-pondeuses" icon="egg" title="Fiches Pondeuses" description="Suivi quotidien de la ponte et récolte d'œufs" />
        <x-nav-card href="/fiche-volailles-reproducteurs" icon="pets" title="Fiches Volailles" description="Reproducteurs, poussins, Goliath/Chair" />
        <x-nav-card href="/fiche-porcs" icon="pets" title="Fiches Porcs" description="Suivi journalier — Porciculture" />
        @if($this->helicoEnabled)
            <x-nav-card href="{{ route('elevage.fiche-escargots') }}" icon="bug_report" title="Fiches Escargots" description="Héliciculture — suivi mensuel du cheptel" />
        @else
            <a href="{{ route('elevage.fiche-escargots') }}" class="group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all">
                <div class="w-12 h-12 rounded-lg bg-outline-variant/20 flex items-center justify-center flex-shrink-0"><span class="material-symbols-outlined text-outline text-[24px]">bug_report</span></div>
                <div class="min-w-0 flex-1">
                    <p class="text-sm font-bold text-brand-forest">Fiches Escargots</p>
                    <p class="text-[11px] text-outline">Héliciculture — module désactivé</p>
                </div>
                <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
            </a>
        @endif
    </div>

    <h3 class="text-xs font-bold text-brand-forest uppercase tracking-wider mb-sm">Accès Rapides — Élevage &amp; Soins</h3>
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-md mb-lg">
        <x-nav-card href="/suivi-reproduction" icon="favorite" title="Suivi Reproduction" description="Saillies, palpations, mises bas, sevrages" />
        <x-nav-card href="/soins-vaccins-hub" icon="vaccines" title="Soins et Vaccins" description="Registre vétérinaire, calendrier, rémanence" />
        <x-nav-card href="/elevage-dashboard" icon="dashboard" title="Dashboard Élevage" description="GMQ, rentabilité, alertes" />
        <x-nav-card href="/transferts-bandes" icon="swap_horiz" title="Transferts entre Bandes" description="Portées, sevrés, regroupements ; rattachement à la bande d'origine" />
    </div>
</div>
