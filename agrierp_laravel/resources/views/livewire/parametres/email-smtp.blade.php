<div class="mt-md">
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">mail</span>Email (SMTP)
        </h2>
        <p class="text-xs text-outline mt-xs">Serveur d'envoi des e-mails de la ferme (relances, notifications, réinitialisation des mots de passe). Une seule configuration pour toute l'application.</p>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-md">
        <div class="bg-white border border-outline-variant rounded-lg p-lg space-y-md">
            <h3 class="text-sm font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">mail</span>Serveur SMTP</h3>
            <form wire:submit="save" class="space-y-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Hôte SMTP *</label>
                    <input wire:model="smtpHost" type="text" placeholder="ex : smtp.gmail.com" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('smtpHost') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('smtpHost') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div class="grid grid-cols-2 gap-sm">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Port *</label>
                        <input wire:model="smtpPort" type="number" placeholder="587" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('smtpPort') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('smtpPort') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Sécurité</label>
                        <select wire:model="smtpSecurity" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                            @foreach(\App\Livewire\Parametres\EmailSmtp::SECURITES as $valeur => $libelle)
                                <option value="{{ $valeur }}">{{ $libelle }}</option>
                            @endforeach
                        </select>
                        @error('smtpSecurity') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Utilisateur SMTP</label>
                    <input wire:model="smtpUser" type="text" placeholder="ex : notifications@fermeolouwachegoun.com" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    @error('smtpUser') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Mot de Passe SMTP</label>
                    <input wire:model="smtpPassword" type="password" autocomplete="new-password" placeholder="Laisser vide pour conserver le mot de passe actuel" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    @error('smtpPassword') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    <div class="flex items-center justify-between gap-sm mt-xs">
                        @if($this->motDePasseEnregistre)
                            <p dusk="smtp-mot-de-passe-etat" class="text-[10px] text-brand-emerald font-bold flex items-center gap-1"><span class="material-symbols-outlined text-[14px]">lock</span>Mot de passe enregistré</p>
                            <button type="button" x-on:click="$dispatch('open-modal', { name: 'effacer-mot-de-passe-smtp' })" class="text-[10px] font-bold text-error-deep hover:underline">Effacer le mot de passe</button>
                        @else
                            <p dusk="smtp-mot-de-passe-etat" class="text-[10px] text-outline">Aucun mot de passe enregistré</p>
                        @endif
                    </div>
                    <p class="text-[10px] text-outline mt-xs">Chiffré en base — jamais réaffiché en clair une fois enregistré, jamais envoyé aux postes.</p>
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Adresse d'Expédition</label>
                    <input wire:model="fromAddress" type="email" placeholder="{{ $this->contactEmail ?? 'ex : contact@fermeolouwachegoun.com' }}" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('fromAddress') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('fromAddress') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    <p class="text-[10px] text-outline mt-xs">Vide : l'e-mail de contact (Données de l'Entreprise) sert d'expéditeur.</p>
                </div>
                <button type="submit" wire:loading.attr="disabled" wire:target="save" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm disabled:opacity-50">Enregistrer la Configuration SMTP</button>
            </form>
        </div>

        <div class="bg-white border border-outline-variant rounded-lg p-lg space-y-md self-start">
            <h3 class="text-sm font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">send</span>Envoyer un e-mail de test</h3>
            <p class="text-[11px] text-outline">Le test emploie la configuration <strong>enregistrée</strong> : enregistrez d'abord une modification avant de la tester. Un e-mail part réellement.</p>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Destinataire du test</label>
                <input wire:model="testEmailTo" type="email" placeholder="Envoyer un e-mail de test à..." class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('testEmailTo') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('testEmailTo') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <button type="button" wire:click="sendTestEmail" wire:loading.attr="disabled" wire:target="sendTestEmail" class="w-full md:w-auto flex items-center justify-center gap-xs py-sm px-lg rounded-lg border border-outline-variant bg-white hover:bg-surface-zebra text-brand-forest font-bold text-xs disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">send</span>Envoyer un e-mail de test
            </button>
            <div class="bg-surface-zebra rounded-lg p-sm text-[11px] text-outline">
                Chaque poste Windows a son propre réglage SMTP (Paramètres &gt; Email (SMTP) du poste) : son mot de passe reste dans le coffre du système de ce poste et ne transite jamais par le serveur.
            </div>
        </div>
    </div>

    @if($this->motDePasseEnregistre)
    <x-modal-confirm-hard-delete
        name="effacer-mot-de-passe-smtp"
        item-label="Le mot de passe SMTP enregistré"
        action="effacerMotDePasse"
        title="Effacer le mot de passe"
        confirm-label="Effacer le mot de passe"
        warning="Si le serveur d'envoi exige une authentification, aucun e-mail ne partira plus tant qu'un nouveau mot de passe n'aura pas été saisi." />
    @endif
</div>
