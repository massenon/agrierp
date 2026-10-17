<div class="mt-md space-y-md">
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">admin_panel_settings</span>Rôles &amp; Permissions
            </h2>
            <p class="text-xs text-outline mt-xs">Matrice de droits d'accès et sauvegardes de la base de données.</p>
        </div>
        <div class="flex items-center gap-xs">
            <button type="button" wire:click="exportRolesPdf" wire:loading.attr="disabled" wire:target="exportRolesPdf" class="flex items-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
            </button>
            @if($this->isAdmin)
                <button type="button" wire:click="newRole" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                    <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouveau Rôle
                </button>
            @endif
        </div>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-md">
        <x-kpi-card label="Rôles configurés" icon="shield" color="emerald" :value="$this->kpis['roles']" />
        <x-kpi-card label="Utilisateurs assignés" icon="group" color="blue" :value="$this->kpis['utilisateurs']" />
        <x-kpi-card label="Modules couverts" icon="apps" color="maize" :value="$this->kpis['modules']" />
        <x-kpi-card label="Dernière sauvegarde" icon="backup" color="emerald" :value="$this->kpis['derniere_sauvegarde']" />
    </div>

    @unless($this->isAdmin)
        <div class="bg-accent-yellow/10 border border-accent-yellow/40 rounded-lg p-md text-xs text-brand-forest flex items-start gap-xs">
            <span class="material-symbols-outlined text-brand-forest text-[18px] flex-shrink-0">lock</span>
            <span>Seul l'administrateur peut créer, modifier ou supprimer un rôle. Vous pouvez consulter la matrice ci-dessous en lecture seule.</span>
        </div>
    @endunless

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="px-md py-sm border-b border-outline-variant"><h3 class="text-sm font-bold text-brand-forest">Matrice des Droits d'Accès</h3></div>
        <div class="overflow-x-auto">
            <table class="w-full text-xs">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[9px] text-outline font-bold uppercase">Rôle</th>
                        @foreach($this->modules as $module)
                            <th class="px-sm py-sm text-center text-[9px] text-outline font-bold uppercase whitespace-nowrap">{{ $module }}</th>
                        @endforeach
                        @if($this->isAdmin)
                            <th class="px-sm py-sm text-right text-[9px] text-outline font-bold uppercase whitespace-nowrap">Actions</th>
                        @endif
                    </tr>
                </thead>
                <tbody>
                    @foreach($this->roles as $i => $row)
                        <tr class="{{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} border-b border-outline-variant">
                            <td class="px-md py-sm text-xs font-bold text-brand-forest whitespace-nowrap">
                                {{ ucfirst($row['role']->name) }}
                                @if($row['role']->name === 'admin')
                                    <span class="material-symbols-outlined text-[13px] text-outline align-middle" title="Rôle protégé, ne peut pas être supprimé">lock</span>
                                @endif
                            </td>
                            @foreach($row['modules'] as $granted)
                                <td class="px-sm py-sm text-center">
                                    @if($granted)
                                        <span class="material-symbols-outlined text-brand-emerald text-[18px]">check_circle</span>
                                    @else
                                        <span class="material-symbols-outlined text-outline-variant text-[18px]">remove</span>
                                    @endif
                                </td>
                            @endforeach
                            @if($this->isAdmin)
                                <td class="px-sm py-sm text-right whitespace-nowrap">
                                    <button type="button" wire:click="editRole('{{ $row['role']->name }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier le rôle"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                    @if($row['role']->name !== 'admin')
                                        <button type="button" x-on:click="$dispatch('open-modal', { name: 'delete-role-{{ $row['role']->name }}' })" class="text-error-deep hover:text-red-800 p-1" title="Supprimer le rôle"><span class="material-symbols-outlined text-[18px]">delete</span></button>
                                    @endif
                                </td>
                            @endif
                        </tr>
                        @if($this->isAdmin && $row['role']->name !== 'admin')
                            <x-modal-confirm-hard-delete
                                :name="'delete-role-'.$row['role']->name"
                                :item-label="'Le rôle « '.$row['role']->name.' »'"
                                :action="'deleteRole(\''.$row['role']->name.'\')'"
                                :warning="$row['users_count'] > 0 ? $row['users_count'].' utilisateur(s) porte(nt) encore ce rôle — la suppression sera refusée tant qu\'ils y sont assignés.' : null" />
                        @endif
                    @endforeach
                </tbody>
            </table>
        </div>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="text-sm font-bold text-brand-forest flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">backup</span>Sauvegardes de la Base de Données</h3>
            <button type="button" wire:click="generateBackup" wire:loading.attr="disabled" wire:target="generateBackup" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">save</span>Générer une Sauvegarde
            </button>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full text-xs">
                <thead><tr class="text-outline border-b border-outline-variant"><th class="text-left py-xs">Fichier</th><th class="text-left py-xs">Date</th><th class="text-right py-xs">Taille</th><th class="text-right py-xs">Actions</th></tr></thead>
                <tbody>
                    @forelse($this->backups as $i => $backup)
                        <tr class="border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : '' }}">
                            <td class="py-xs font-mono">{{ $backup['name'] }}</td>
                            <td class="py-xs">{{ $backup['date'] }}</td>
                            <td class="py-xs text-right">{{ $backup['size'] }}</td>
                            <td class="py-xs text-right"><button type="button" wire:click="downloadBackup('{{ $backup['path'] }}')" class="text-brand-emerald"><span class="material-symbols-outlined text-[16px]">download</span></button></td>
                        </tr>
                    @empty
                        <tr><td colspan="4" class="py-md text-center text-outline">Aucune sauvegarde générée pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    @if($this->isAdmin)
        <x-modal name="modal-edit-role" max-width="md">
            <div class="flex items-center justify-between mb-md">
                <h3 class="font-bold text-lg text-brand-forest">{{ $editingRoleName ? 'Modifier le Rôle — '.ucfirst($editingRoleName) : 'Nouveau Rôle' }}</h3>
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-edit-role' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
            </div>
            <form wire:submit="saveRole" class="space-y-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nom du rôle *</label>
                    <input wire:model="roleName" type="text" placeholder="ex : responsable-achats" {{ $editingRoleName === 'admin' ? 'disabled' : '' }} class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('roleName') ? 'is-invalid' : 'border-outline-variant' }} {{ $editingRoleName === 'admin' ? 'bg-surface-zebra' : '' }}">
                    @error('roleName') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    <p class="text-[10px] text-outline mt-xs">Lettres minuscules, chiffres et tirets uniquement.</p>
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Modules autorisés</label>
                    <div class="grid grid-cols-2 gap-1 text-xs max-h-64 overflow-y-auto">
                        @foreach($editingPermissions as $permission => $granted)
                            <label class="flex items-center gap-1">
                                <input type="checkbox" wire:model="editingPermissions.{{ $permission }}" class="rounded border-outline-variant text-brand-emerald">
                                {{ $permission }}
                            </label>
                        @endforeach
                    </div>
                </div>
                <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                    <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-edit-role' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                    <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
                </div>
            </form>
        </x-modal>
    @endif
</div>
