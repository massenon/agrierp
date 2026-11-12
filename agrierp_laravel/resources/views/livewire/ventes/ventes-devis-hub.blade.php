<div>
    {{-- CONF-4 : sans `manage-ventes` (comptable : lecture), l'onglet de la caisse n'existe pas. --}}
    <x-tab-page
        :tabs="collect([
            ['key' => 'vente', 'label' => __('ventes.tab_enregistrer_vente'), 'icon' => 'point_of_sale'],
            ['key' => 'devis', 'label' => __('ventes.tab_devis_prestations'), 'icon' => 'description'],
            ['key' => 'historique', 'label' => __('ventes.tab_historique_ventes'), 'icon' => 'history'],
            ['key' => 'retours', 'label' => __('ventes.tab_retours_avoirs'), 'icon' => 'assignment_return'],
            ['key' => 'cloture', 'label' => __('ventes.tab_cloture_caisse'), 'icon' => 'point_of_sale'],
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
