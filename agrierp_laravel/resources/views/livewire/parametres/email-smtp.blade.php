<div class="mt-md">
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">mail</span>{{ __('parametres.titre_email_smtp') }}
        </h2>
        <p class="text-xs text-outline mt-xs">{{ __('parametres.desc_email_smtp') }}</p>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-md">
        <div class="bg-white border border-outline-variant rounded-lg p-lg space-y-md">
            <h3 class="text-sm font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">mail</span>{{ __('parametres.section_serveur_smtp') }}</h3>
            <form wire:submit="save" class="space-y-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_hote_smtp') }}</label>
                    <input wire:model="smtpHost" type="text" placeholder="ex : smtp.gmail.com" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('smtpHost') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('smtpHost') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div class="grid grid-cols-2 gap-sm">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_port_smtp') }}</label>
                        <input wire:model="smtpPort" type="number" placeholder="587" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('smtpPort') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('smtpPort') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_securite_smtp') }}</label>
                        <select wire:model="smtpSecurity" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                            @foreach(\App\Livewire\Parametres\EmailSmtp::SECURITES as $valeur => $libelle)
                                <option value="{{ $valeur }}">{{ $libelle }}</option>
                            @endforeach
                        </select>
                        @error('smtpSecurity') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_utilisateur_smtp') }}</label>
                    <input wire:model="smtpUser" type="text" placeholder="ex : notifications@fermeolouwachegoun.com" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    @error('smtpUser') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_mdp_smtp') }}</label>
                    <input wire:model="smtpPassword" type="password" autocomplete="new-password" placeholder="{{ __('parametres.placeholder_mdp_smtp') }}" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    @error('smtpPassword') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    <div class="flex items-center justify-between gap-sm mt-xs">
                        @if($this->motDePasseEnregistre)
                            <p dusk="smtp-mot-de-passe-etat" class="text-[10px] text-brand-emerald font-bold flex items-center gap-1"><span class="material-symbols-outlined text-[14px]">lock</span>{{ __('parametres.mdp_smtp_enregistre') }}</p>
                            <button type="button" x-on:click="$dispatch('open-modal', { name: 'effacer-mot-de-passe-smtp' })" class="text-[10px] font-bold text-error-deep hover:underline">{{ __('parametres.lien_effacer_mdp_smtp') }}</button>
                        @else
                            <p dusk="smtp-mot-de-passe-etat" class="text-[10px] text-outline">{{ __('parametres.mdp_smtp_vide') }}</p>
                        @endif
                    </div>
                    <p class="text-[10px] text-outline mt-xs">{{ __('parametres.aide_mdp_smtp') }}</p>
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_adresse_expedition') }}</label>
                    <input wire:model="fromAddress" type="email" placeholder="{{ $this->contactEmail ?? 'ex : contact@fermeolouwachegoun.com' }}" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('fromAddress') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('fromAddress') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    <p class="text-[10px] text-outline mt-xs">{{ __('parametres.aide_adresse_expedition') }}</p>
                </div>
                <button type="submit" wire:loading.attr="disabled" wire:target="save" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm disabled:opacity-50">{{ __('parametres.btn_enregistrer_smtp') }}</button>
            </form>
        </div>

        <div class="bg-white border border-outline-variant rounded-lg p-lg space-y-md self-start">
            <h3 class="text-sm font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">send</span>{{ __('parametres.section_test_email') }}</h3>
            <p class="text-[11px] text-outline">{{ __('parametres.desc_test_email') }}</p>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_destinataire_test') }}</label>
                <input wire:model="testEmailTo" type="email" placeholder="{{ __('parametres.placeholder_destinataire_test') }}" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('testEmailTo') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('testEmailTo') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <button type="button" wire:click="sendTestEmail" wire:loading.attr="disabled" wire:target="sendTestEmail" class="w-full md:w-auto flex items-center justify-center gap-xs py-sm px-lg rounded-lg border border-outline-variant bg-white hover:bg-surface-zebra text-brand-forest font-bold text-xs disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">send</span>{{ __('parametres.btn_envoyer_test') }}
            </button>
            <div class="bg-surface-zebra rounded-lg p-sm text-[11px] text-outline">
                {{ __('parametres.info_smtp_postes') }}
            </div>
        </div>
    </div>

    @if($this->motDePasseEnregistre)
    <x-modal-confirm-hard-delete
        name="effacer-mot-de-passe-smtp"
        :item-label="__('parametres.modal_effacer_mdp_smtp_item')"
        action="effacerMotDePasse"
        :title="__('parametres.modal_effacer_mdp_smtp_titre')"
        :confirm-label="__('parametres.modal_effacer_mdp_smtp_confirmer')"
        :warning="__('parametres.modal_effacer_mdp_smtp_warning')" />
    @endif
</div>
