<div class="mt-md space-y-md">
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">manage_accounts</span>{{ __('parametres.titre_gestion_utilisateurs') }}
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">{{ __('parametres.desc_gestion_utilisateurs') }}</p>
        </div>
        <div class="flex items-center gap-xs">
            <button type="button" wire:click="exportUtilisateursPdf" wire:loading.attr="disabled" wire:target="exportUtilisateursPdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>{{ __('parametres.btn_exporter_pdf') }}
            </button>
            @can('manage-users')
            {{-- Ticket 15.54 — vider les sessions (web et postes), session en cours conservée. --}}
            <button type="button" x-on:click="$dispatch('open-modal', { name: 'modal-vider-sessions' })" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-error-deep font-bold text-xs px-md py-sm rounded-full transition-all">
                <span class="material-symbols-outlined text-[18px]">logout</span>{{ __('parametres.btn_deconnecter_sessions') }}
            </button>
            <button type="button" wire:click="newUser" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
                <span class="material-symbols-outlined text-[18px]">add_circle</span>{{ __('parametres.btn_nouvel_utilisateur') }}
            </button>
            @endcan
        </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <x-kpi-card :label="__('parametres.kpi_utilisateurs_actifs')" icon="group" color="emerald" :value="$this->kpis['utilisateurs_actifs']" />
        <x-kpi-card :label="__('parametres.kpi_roles_definis')" icon="badge" color="blue" :value="$this->kpis['roles_definis']" />
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md flex flex-col md:flex-row items-stretch md:items-center justify-between gap-sm border-b border-outline-variant">
            <div class="relative flex-1 md:max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
            </div>
            <select wire:model.live="statusFilter" class="border border-outline-variant rounded-lg text-xs px-sm py-2 bg-white w-full md:w-auto">
                <option value="">{{ __('parametres.filtre_tous_statuts') }}</option>
                <option value="Actif">{{ __('parametres.statut_actif') }}</option>
                <option value="Désactivé">{{ __('parametres.statut_desactive') }}</option>
            </select>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_nom') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_email') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_role') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_statut') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_actions') }}</th>
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
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">{{ __('parametres.statut_actif') }}</span>
                                    @if($user->must_change_password)
                                        <span class="block text-[10px] text-outline mt-xs">{{ __('parametres.statut_mdp_changer') }}</span>
                                    @endif
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-surface-zebra text-outline border-outline-variant">{{ __('parametres.statut_desactive') }}</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                @can('manage-users')
                                <button type="button" wire:click="editUser('{{ $user->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="{{ __('parametres.title_modifier') }}"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                @if($user->is_active)
                                    <button type="button" wire:click="resetPasswordUser('{{ $user->id }}')" class="text-brand-forest hover:text-brand-emerald p-1" title="{{ __('parametres.title_reinit_mdp') }}"><span class="material-symbols-outlined text-[18px]">lock_reset</span></button>
                                    <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-user-{{ $user->id }}' })" class="text-error-deep hover:text-red-800 p-1" title="{{ __('parametres.title_archiver') }}"><span class="material-symbols-outlined text-[18px]">archive</span></button>
                                @else
                                    <button type="button" wire:click="reactivateUser('{{ $user->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="{{ __('parametres.title_reactiver') }}"><span class="material-symbols-outlined text-[18px]">restart_alt</span></button>
                                @endif
                                @else
                                <span class="text-outline text-[10px] italic">{{ __('parametres.label_lecture_seule') }}</span>
                                @endcan
                            </td>
                        </tr>
                        <x-modal-confirm-delete :name="'archive-user-'.$user->id" :item-label="$user->name" :action="'archiveUser(\''.$user->id.'\')'" />
                    @empty
                        <tr><td colspan="5" class="px-md py-lg text-center text-outline">{{ __('parametres.msg_aucun_utilisateur') }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-vider-sessions" max-width="sm">
        <div class="text-center">
            <span class="material-symbols-outlined text-error-deep" style="font-size:48px;">logout</span>
            <h3 class="font-bold text-lg text-brand-forest mt-sm">{{ __('parametres.titre_vider_sessions') }}</h3>
            <p class="text-xs text-outline mt-xs">{{ __('parametres.desc_vider_sessions') }}</p>
            <div class="flex justify-center gap-sm mt-lg">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-vider-sessions' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('parametres.btn_annuler') }}</button>
                <button type="button" wire:click="viderSessions" class="px-md py-sm rounded-lg bg-error-red text-white text-sm font-bold">{{ __('parametres.btn_deconnecter') }}</button>
            </div>
        </div>
    </x-modal>

    <x-modal name="modal-reinitialiser-mot-de-passe" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ __('parametres.titre_reinit_mdp') }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-reinitialiser-mot-de-passe' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="reinitialiserMotDePasse" class="space-y-md">
            <p class="text-xs text-outline">{{ __('parametres.desc_reinit_mdp') }}</p>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_mdp_temp') }}</label>
                <input wire:model="motDePasseTemporaire" type="password" autocomplete="new-password" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('motDePasseTemporaire') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('motDePasseTemporaire') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="flex justify-end gap-sm pt-md border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-reinitialiser-mot-de-passe' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('parametres.btn_annuler') }}</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ __('parametres.btn_reinitialiser') }}</button>
            </div>
        </form>
    </x-modal>

    <x-modal name="modal-create-gestion-utilisateurs" max-width="lg">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingUserId ? __('parametres.titre_modifier_utilisateur') : __('parametres.titre_creer_utilisateur') }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-gestion-utilisateurs' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveUser" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_nom_complet') }}</label>
                <input wire:model="name" type="text" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('name') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('name') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_nom_utilisateur') }}</label>
                <input wire:model="username" type="text" placeholder="ex : compta" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('username') ? 'is-invalid' : 'border-outline-variant' }}">
                <p class="text-[10px] text-outline mt-xs">{{ __('parametres.aide_nom_utilisateur') }}</p>
                @error('username') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_email_utilisateur') }}</label>
                <input wire:model="email" type="email" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('email') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('email') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_role_utilisateur') }}</label>
                <select wire:model="role" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('role') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">{{ __('parametres.placeholder_selectionner') }}</option>
                    @foreach($this->rolesList as $r)
                        <option value="{{ $r->name }}">{{ ucfirst($r->name) }}</option>
                    @endforeach
                </select>
                @error('role') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ $editingUserId ? __('parametres.label_mdp_utilisateur_modif') : __('parametres.label_mdp_utilisateur') }}</label>
                <input wire:model="password" type="password" placeholder="{{ $editingUserId ? __('parametres.placeholder_mdp_conserver') : __('parametres.placeholder_mdp_min8') }}" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('password') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('password') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="flex justify-end gap-sm pt-md border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-gestion-utilisateurs' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('parametres.btn_annuler') }}</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ __('parametres.btn_enregistrer_utilisateur') }}</button>
            </div>
        </form>
    </x-modal>
</div>
