<div class="mt-md space-y-md">
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">manage_accounts</span>Gestion des Utilisateurs
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Administration des comptes d'accès à AgriERP.</p>
        </div>
        <div class="flex items-center gap-xs">
            <button type="button" wire:click="exportUtilisateursPdf" wire:loading.attr="disabled" wire:target="exportUtilisateursPdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
            </button>
            @can('manage-users')
            <button type="button" wire:click="newUser" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
                <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouvel Utilisateur
            </button>
            @endcan
        </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <x-kpi-card label="Utilisateurs actifs" icon="group" color="emerald" :value="$this->kpis['utilisateurs_actifs']" />
        <x-kpi-card label="Rôles définis" icon="badge" color="blue" :value="$this->kpis['roles_definis']" />
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md flex flex-col md:flex-row items-stretch md:items-center justify-between gap-sm border-b border-outline-variant">
            <div class="relative flex-1 md:max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
            </div>
            <select wire:model.live="statusFilter" class="border border-outline-variant rounded-lg text-xs px-sm py-2 bg-white w-full md:w-auto">
                <option value="">Tous les statuts</option>
                <option value="Actif">Actif</option>
                <option value="Désactivé">Désactivé</option>
            </select>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Nom</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Email</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Rôle</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->users as $i => $user)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Nom" class="px-md py-sm text-xs">
                                {{ $user->name }}
                                @if($user->username)
                                    <span class="block text-[10px] text-outline font-mono">{{ $user->username }}</span>
                                @endif
                            </td>
                            <td data-label="Email" class="px-md py-sm text-xs">{{ $user->email }}</td>
                            <td data-label="Rôle" class="px-md py-sm text-xs">{{ $user->role_label ?? '—' }}</td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($user->is_active)
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Actif</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-surface-zebra text-outline border-outline-variant">Désactivé</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                @can('manage-users')
                                <button type="button" wire:click="editUser('{{ $user->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                @if($user->is_active)
                                    <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-user-{{ $user->id }}' })" class="text-error-deep hover:text-red-800 p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">archive</span></button>
                                @else
                                    <button type="button" wire:click="reactivateUser('{{ $user->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="Réactiver"><span class="material-symbols-outlined text-[18px]">restart_alt</span></button>
                                @endif
                                @else
                                <span class="text-outline text-[10px] italic">Lecture seule</span>
                                @endcan
                            </td>
                        </tr>
                        <x-modal-confirm-delete :name="'archive-user-'.$user->id" :item-label="$user->name" :action="'archiveUser(\''.$user->id.'\')'" />
                    @empty
                        <tr><td colspan="5" class="px-md py-lg text-center text-outline">Aucun utilisateur pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-create-gestion-utilisateurs" max-width="lg">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingUserId ? "Modifier l'Utilisateur" : 'Nouvel Utilisateur' }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-gestion-utilisateurs' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveUser" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nom complet *</label>
                <input wire:model="name" type="text" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('name') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('name') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nom d'utilisateur *</label>
                <input wire:model="username" type="text" placeholder="ex : compta" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('username') ? 'is-invalid' : 'border-outline-variant' }}">
                <p class="text-[10px] text-outline mt-xs">Lettres, chiffres, point, tiret et souligne. Sans arobase.</p>
                @error('username') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Email *</label>
                <input wire:model="email" type="email" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('email') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('email') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Rôle *</label>
                <select wire:model="role" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('role') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->rolesList as $r)
                        <option value="{{ $r->name }}">{{ ucfirst($r->name) }}</option>
                    @endforeach
                </select>
                @error('role') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ $editingUserId ? 'Nouveau mot de passe' : 'Mot de passe *' }}</label>
                <input wire:model="password" type="password" placeholder="{{ $editingUserId ? 'Laisser vide pour conserver le mot de passe actuel' : 'Minimum 8 caractères' }}" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('password') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('password') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="flex justify-end gap-sm pt-md border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-gestion-utilisateurs' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>
</div>
