<div>
    <x-tab-page
        :tabs="[
            ['key' => 'employes', 'label' => 'Registre Employés', 'icon' => 'badge'],
            ['key' => 'stagiaires', 'label' => 'Registre Stagiaires', 'icon' => 'school'],
            ['key' => 'pointage', 'label' => 'Feuille de Pointage', 'icon' => 'schedule'],
            ['key' => 'paie', 'label' => 'Gestion de la Paie', 'icon' => 'payments'],
            ['key' => 'attestations', 'label' => 'Attestations', 'icon' => 'description'],
        ]"
        :active="$tab">

        @if($tab === 'employes')
            <livewire:r-h.registre-employes />
        @endif

        @if($tab === 'stagiaires')
            <livewire:r-h.registre-stagiaires />
        @endif

        @if($tab === 'pointage')
            <livewire:r-h.feuille-pointage />
        @endif

        @if($tab === 'paie')
            <livewire:r-h.gestion-paie />
        @endif

        @if($tab === 'attestations')
            <livewire:r-h.attestations />
        @endif
    </x-tab-page>
</div>
