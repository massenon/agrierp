<div>
    <x-tab-page
        :tabs="[
            ['key' => 'roles', 'label' => 'Rôles & Permissions', 'icon' => 'admin_panel_settings'],
            ['key' => 'entreprise', 'label' => 'Données de l\'Entreprise', 'icon' => 'business'],
            ['key' => 'email', 'label' => 'Email (SMTP)', 'icon' => 'mail'],
            ['key' => 'modules', 'label' => 'Modules Actifs', 'icon' => 'apps'],
            ['key' => 'utilisateurs', 'label' => 'Gestion Utilisateurs', 'icon' => 'group'],
            ['key' => 'postes', 'label' => 'Postes & Appairage', 'icon' => 'lan'],
            ['key' => 'paiement', 'label' => 'Modes de Paiement', 'icon' => 'payments'],
            ['key' => 'audit', 'label' => 'Audit Logs', 'icon' => 'history'],
            ['key' => 'restauration', 'label' => 'Restauration', 'icon' => 'restore_from_trash'],
            ['key' => 'reinitialisation', 'label' => 'Réinitialisation', 'icon' => 'restart_alt'],
            ['key' => 'sauvegardes', 'label' => 'Sauvegardes', 'icon' => 'database'],
        ]"
        :active="$tab">

        @if($tab === 'roles')
            <livewire:parametres.roles-permissions />
        @endif

        @if($tab === 'entreprise')
            <livewire:parametres.donnees-entreprise />
        @endif

        @if($tab === 'email')
            <livewire:parametres.email-smtp />
        @endif

        @if($tab === 'modules')
            <livewire:parametres.modules-actifs />
        @endif

        @if($tab === 'utilisateurs')
            <livewire:parametres.gestion-utilisateurs />
        @endif

        @if($tab === 'postes')
            <livewire:parametres.postes-appairage />
        @endif

        @if($tab === 'paiement')
            <livewire:parametres.modes-paiement />
        @endif

        @if($tab === 'audit')
            <livewire:parametres.audit-logs />
        @endif

        @if($tab === 'restauration')
            <livewire:parametres.restauration />
        @endif

        @if($tab === 'reinitialisation')
            <livewire:parametres.reinitialisation-donnees />
        @endif

        @if($tab === 'sauvegardes')
            <livewire:parametres.sauvegardes />
        @endif
    </x-tab-page>
</div>
