<div>
    <x-tab-page
        :tabs="[
            ['key' => 'roles', 'label' => __('parametres.onglet_roles'), 'icon' => 'admin_panel_settings'],
            ['key' => 'entreprise', 'label' => __('parametres.onglet_entreprise'), 'icon' => 'business'],
            ['key' => 'facturation', 'label' => __('parametres.onglet_facturation'), 'icon' => 'receipt_long'],
            ['key' => 'email', 'label' => __('parametres.onglet_email'), 'icon' => 'mail'],
            ['key' => 'modules', 'label' => __('parametres.onglet_modules'), 'icon' => 'apps'],
            ['key' => 'utilisateurs', 'label' => __('parametres.onglet_utilisateurs'), 'icon' => 'group'],
            ['key' => 'postes', 'label' => __('parametres.onglet_postes'), 'icon' => 'lan'],
            ['key' => 'paiement', 'label' => __('parametres.onglet_paiement'), 'icon' => 'payments'],
            ['key' => 'audit', 'label' => __('parametres.onglet_audit'), 'icon' => 'history'],
            ['key' => 'corbeille', 'label' => __('parametres.onglet_corbeille'), 'icon' => 'restore_from_trash'],
            ['key' => 'reinitialisation', 'label' => __('parametres.onglet_reinitialisation'), 'icon' => 'restart_alt'],
            ['key' => 'sauvegardes', 'label' => __('parametres.onglet_sauvegardes'), 'icon' => 'database'],
        ]"
        :active="$tab">

        @if($tab === 'roles')
            <livewire:parametres.roles-permissions />
        @endif

        @if($tab === 'entreprise')
            <livewire:parametres.donnees-entreprise />
        @endif

        @if($tab === 'facturation')
            <livewire:parametres.facturation-emecef />
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

        @if($tab === 'corbeille')
            <livewire:parametres.corbeille />
        @endif

        @if($tab === 'reinitialisation')
            <livewire:parametres.reinitialisation-donnees />
        @endif

        @if($tab === 'sauvegardes')
            <livewire:parametres.sauvegardes />
        @endif
    </x-tab-page>
</div>
