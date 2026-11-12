<div>
    <x-tab-page
        :tabs="[
            ['key' => 'ajouter', 'label' => __('achats.fourn_hub_onglet_ajouter'), 'icon' => 'person_add'],
            ['key' => 'fiches', 'label' => __('achats.fourn_hub_onglet_fiches'), 'icon' => 'contact_page'],
            ['key' => 'dettes', 'label' => __('achats.fourn_hub_onglet_dettes'), 'icon' => 'request_quote'],
        ]"
        :active="$tab">

        @if($tab === 'ajouter')
            <livewire:achats.ajouter-fournisseur />
        @endif

        @if($tab === 'fiches')
            <livewire:achats.fiches-fournisseurs />
        @endif

        @if($tab === 'dettes')
            <livewire:achats.dettes-fournisseurs />
        @endif
    </x-tab-page>
</div>
