<div>
    <x-tab-page
        :tabs="[
            ['key' => 'courriers', 'label' => 'Gestion des Courriers', 'icon' => 'mail'],
            ['key' => 'archivage', 'label' => 'Archivage des Documents', 'icon' => 'archive'],
            ['key' => 'documents', 'label' => 'Documents Administratifs', 'icon' => 'description'],
        ]"
        :active="$tab">

        @if($tab === 'courriers')
            <livewire:administration.gestion-courriers />
        @endif

        @if($tab === 'archivage')
            <livewire:administration.archivage-documents />
        @endif

        @if($tab === 'documents')
            <livewire:administration.documents-administratifs />
        @endif
    </x-tab-page>
</div>
