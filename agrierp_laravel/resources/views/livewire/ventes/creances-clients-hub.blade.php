<div>
    <x-tab-page
        :tabs="[
            ['key' => 'liste', 'label' => __('ventes.tab_liste_clients'), 'icon' => 'groups'],
            ['key' => 'dettes', 'label' => __('ventes.tab_suivi_dettes'), 'icon' => 'request_quote'],
            ['key' => 'relances', 'label' => __('ventes.tab_relances_clients'), 'icon' => 'notifications_active'],
            ['key' => 'avances', 'label' => __('ventes.tab_historique_avances_court'), 'icon' => 'savings'],
        ]"
        :active="$tab">

        @if($tab === 'liste')
            <livewire:ventes.liste-clients />
        @endif

        @if($tab === 'dettes')
            <livewire:ventes.suivi-dettes />
        @endif

        @if($tab === 'relances')
            <livewire:ventes.relances-clients />
        @endif

        @if($tab === 'avances')
            <livewire:ventes.historique-avances />
        @endif
    </x-tab-page>
</div>
