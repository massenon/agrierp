<div>
    <x-tab-page
        :tabs="[
            ['key' => 'vente', 'label' => 'Enregistrer Vente', 'icon' => 'point_of_sale'],
            ['key' => 'devis', 'label' => 'Devis Prestations', 'icon' => 'description'],
            ['key' => 'historique', 'label' => 'Historique des Ventes', 'icon' => 'history'],
            ['key' => 'retours', 'label' => 'Retours et Avoirs', 'icon' => 'assignment_return'],
        ]"
        :active="$tab">

        @if($tab === 'vente')
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
    </x-tab-page>
</div>
