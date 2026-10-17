<div>
    <x-tab-page
        :tabs="[
            ['key' => 'ajouter', 'label' => 'Ajouter Fournisseur', 'icon' => 'person_add'],
            ['key' => 'fiches', 'label' => 'Fiches Fournisseurs', 'icon' => 'contact_page'],
            ['key' => 'dettes', 'label' => 'Dettes Fournisseurs', 'icon' => 'request_quote'],
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
