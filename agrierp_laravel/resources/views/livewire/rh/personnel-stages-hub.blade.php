<div>
    <x-tab-page
        :tabs="[
            ['key' => 'employes', 'label' => __('rh.tab_registre_employes'), 'icon' => 'badge'],
            ['key' => 'stagiaires', 'label' => __('rh.tab_registre_stagiaires'), 'icon' => 'school'],
            ['key' => 'pointage', 'label' => __('rh.tab_feuille_pointage'), 'icon' => 'schedule'],
            ['key' => 'paie', 'label' => __('rh.tab_gestion_paie'), 'icon' => 'payments'],
            ['key' => 'attestations', 'label' => __('rh.tab_attestations'), 'icon' => 'description'],
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
