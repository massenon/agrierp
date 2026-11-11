<div>
    {{-- CONF-4 : sans `manage-ventes` (comptable : lecture), l'onglet de la caisse n'existe pas. --}}
    <x-tab-page
        :tabs="collect([
            ['key' => 'vente', 'label' => 'Enregistrer Vente', 'icon' => 'point_of_sale'],
            ['key' => 'devis', 'label' => 'Devis Prestations', 'icon' => 'description'],
            ['key' => 'historique', 'label' => 'Historique des Ventes', 'icon' => 'history'],
            ['key' => 'retours', 'label' => 'Retours et Avoirs', 'icon' => 'assignment_return'],
            ['key' => 'cloture', 'label' => 'Clôture Caisse', 'icon' => 'point_of_sale'],
        ])->reject(fn ($t) => in_array($t['key'], ['vente', 'cloture']) && ! $peutEncaisser)->values()->all()"
        :active="$tab">

        @if($tab === 'vente' && $peutEncaisser)
            <livewire:ventes.pos-interface />
        @endif

        @if($tab === 'devis')
            <livewire:ventes.devis />
        @endif

        @if($tab === 'historique')
            <livewire:ventes.historique-ventes />
        @endif

        @if($tab === 'retours')
            <livewire:ventes.retours-avoirs />
        @endif

        @if($tab === 'cloture' && $peutEncaisser)
            <livewire:ventes.cloture-caisse />
        @endif
    </x-tab-page>
</div>
