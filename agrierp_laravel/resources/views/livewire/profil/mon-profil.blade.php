<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">person</span>Mon Profil
        </h2>
        <p class="text-xs text-outline mt-xs">Informations de session, sécurité et journal d'activité personnel.</p>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-[35%_65%] gap-md items-start">

        <div class="bg-white border border-outline-variant rounded-lg p-lg text-center space-y-md">
            <div class="w-16 h-16 rounded-full bg-brand-emerald text-white flex items-center justify-center text-xl font-extrabold mx-auto">{{ auth()->user()->initials }}</div>
            <div>
                <p class="font-bold text-brand-forest">{{ auth()->user()->name }}</p>
                <p class="text-xs text-outline">{{ auth()->user()->email }}</p>
            </div>
            @if(auth()->user()->role_label)
                <span class="inline-block text-[10px] font-bold px-sm py-1 rounded-full bg-brand-emerald/10 text-brand-emerald border border-brand-emerald/30">{{ auth()->user()->role_label }}</span>
            @endif
            <div class="bg-surface-zebra rounded-lg p-md text-left space-y-xs">
                <p class="text-[10px] text-outline font-bold uppercase">Métadonnées de Session</p>
                <div class="flex justify-between text-xs">
                    <span class="text-outline">Dernière connexion</span>
                    <span class="font-bold">{{ $this->lastLogin?->created_at->format('d/m/Y H:i') ?? '—' }}</span>
                </div>
                <div class="flex justify-between text-xs">
                    <span class="text-outline">Adresse IP</span>
                    <span class="font-mono">{{ $this->lastLogin?->ip_address ?? '—' }}</span>
                </div>
                <div class="flex justify-between text-xs">
                    <span class="text-outline">Statut du compte</span>
                    <span class="font-bold {{ auth()->user()->is_active ? 'text-brand-emerald' : 'text-error-deep' }}">{{ auth()->user()->is_active ? 'Actif' : 'Inactif' }}</span>
                </div>
            </div>
            <p class="text-[10px] text-outline bg-info-blue/10 border border-info-blue/20 rounded-lg p-sm">Ces informations sont en lecture seule. Seul un Directeur Général peut modifier les détails du profil depuis Paramètres &gt; Gestion Utilisateurs.</p>
        </div>

        <div class="space-y-md">
            <div class="bg-white border border-outline-variant rounded-lg p-md">
                <p class="text-xs font-bold text-brand-forest uppercase mb-md flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">lock</span>Modifier le Mot de Passe</p>
                <form wire:submit="updatePassword" class="space-y-md max-w-md">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Ancien mot de passe *</label>
                        <input wire:model="current_password" type="password" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('current_password') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('current_password') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nouveau mot de passe *</label>
                        <input wire:model="new_password" type="password" placeholder="Min. 8 caractères, 1 majuscule, 1 chiffre" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('new_password') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('new_password') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Confirmer le nouveau mot de passe *</label>
                        <input wire:model="new_password_confirmation" type="password" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <button type="submit" class="px-lg py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm">Mettre à jour le mot de passe</button>
                </form>
            </div>

            <div class="bg-white border border-outline-variant rounded-lg overflow-hidden">
                <div class="px-md py-sm border-b border-outline-variant"><h3 class="text-sm font-bold text-brand-forest">Journal d'Audit — 10 Dernières Actions</h3></div>
                @if($this->recentActions->isEmpty())
                    <p class="text-xs text-outline text-center py-lg">Aucune action enregistrée pour le moment.</p>
                @else
                    <div class="overflow-x-auto">
                        <table class="w-full rtable">
                            <thead class="bg-surface-zebra border-b border-outline-variant">
                                <tr>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date / Heure</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Action</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Module</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">IP</th>
                                </tr>
                            </thead>
                            <tbody>
                                @foreach($this->recentActions as $i => $entry)
                                    <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                        <td data-label="Date / Heure" class="px-md py-sm text-xs whitespace-nowrap">{{ $entry->created_at->format('d/m/Y H:i') }}</td>
                                        <td data-label="Action" class="px-md py-sm text-xs">{{ $entry->action_label }}</td>
                                        <td data-label="Module" class="px-md py-sm text-xs text-outline">{{ $entry->module_label ?? '—' }}</td>
                                        <td data-label="IP" class="px-md py-sm text-xs font-mono text-outline">{{ $entry->ip_address ?? '—' }}</td>
                                    </tr>
                                @endforeach
                            </tbody>
                        </table>
                    </div>
                @endif
            </div>
        </div>
    </div>
</div>
