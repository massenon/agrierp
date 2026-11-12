<div>
    <x-tab-page
        :tabs="[
            ['key' => 'enregistrer', 'label' => __('achats.hub_onglet_enregistrer'), 'icon' => 'add_shopping_cart'],
            ['key' => 'liste', 'label' => __('achats.hub_onglet_liste'), 'icon' => 'list_alt'],
            ['key' => 'bons', 'label' => __('achats.hub_onglet_bons'), 'icon' => 'description'],
        ]"
        :active="$tab">

        @if($tab === 'enregistrer')
            <livewire:achats.enregistrer-achat />
        @endif

        @if($tab === 'liste')
            <livewire:achats.liste-achats />
        @endif

        @if($tab === 'bons')
            <livewire:achats.bons-commande />
        @endif
    </x-tab-page>
</div>
