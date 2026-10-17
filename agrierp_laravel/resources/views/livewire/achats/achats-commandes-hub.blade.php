<div>
    <x-tab-page
        :tabs="[
            ['key' => 'enregistrer', 'label' => 'Enregistrer un Achat', 'icon' => 'add_shopping_cart'],
            ['key' => 'liste', 'label' => 'Liste d\'Achats', 'icon' => 'list_alt'],
            ['key' => 'bons', 'label' => 'Bons de Commande', 'icon' => 'description'],
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
