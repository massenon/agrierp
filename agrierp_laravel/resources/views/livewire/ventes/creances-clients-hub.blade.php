<div>
    <x-tab-page
        :tabs="[
            ['key' => 'liste', 'label' => 'Liste des Clients', 'icon' => 'groups'],
            ['key' => 'dettes', 'label' => 'Suivi des Dettes', 'icon' => 'request_quote'],
            ['key' => 'relances', 'label' => 'Relances Clients', 'icon' => 'notifications_active'],
            ['key' => 'avances', 'label' => 'Historique Avances', 'icon' => 'savings'],
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
