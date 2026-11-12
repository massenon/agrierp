<div class="mt-md">
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">domain</span>{{ __('parametres.titre_donnees_entreprise') }}
        </h2>
        <p class="text-xs text-outline mt-xs">{{ __('parametres.desc_donnees_entreprise') }}</p>
    </div>

    <form wire:submit="save" class="space-y-md">
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-md">
            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
                <p class="text-xs font-bold text-brand-forest uppercase">{{ __('parametres.section_infos_generales') }}</p>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_raison_sociale') }}</label>
                    <input wire:model="companyName" type="text" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('companyName') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('companyName') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_nom_promoteur') }}</label>
                    <input wire:model="promoterName" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_adresse_siege') }}</label>
                    <input wire:model="address" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <div class="grid grid-cols-2 gap-sm">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_telephone_principal') }}</label>
                        <input wire:model="phone" type="tel" placeholder="+229 XX XX XX XX" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_email_contact') }}</label>
                        <input wire:model="email" type="email" placeholder="contact@fermeolouwachegoun.com" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('email') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('email') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                </div>
            </div>

            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
                <p class="text-xs font-bold text-brand-forest uppercase">{{ __('parametres.section_infos_legales') }}</p>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_ifu') }}</label>
                    <input wire:model="ifu" type="text" inputmode="numeric" placeholder="ex : 3202601234567" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('ifu') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('ifu') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_rccm') }}</label>
                    <input wire:model="rccm" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <div class="bg-info-blue/10 border border-info-blue/20 rounded-lg p-sm text-[10px] text-brand-forest">{{ __('parametres.info_mecef_facturation') }}</div>
            </div>

            {{-- Ticket CFG-1 — la configuration SMTP a UNE seule saisie : l'onglet « Email (SMTP) » de ce hub. --}}
            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md lg:col-span-2">
                <p class="text-xs font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">mail</span>{{ __('parametres.section_config_email') }}</p>
                <a wire:navigate href="{{ route('parametres.hub', ['tab' => 'email']) }}" class="flex items-center gap-sm p-md rounded-lg border border-outline-variant hover:border-brand-emerald transition-all group">
                    <span class="material-symbols-outlined text-brand-emerald text-[22px]">settings_input_antenna</span>
                    <span class="flex-1">
                        <span class="block text-xs font-bold text-brand-forest">{{ __('parametres.lien_smtp_titre') }}</span>
                        <span class="block text-[11px] text-outline">{{ __('parametres.lien_smtp_detail') }}</span>
                    </span>
                    <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all">chevron_right</span>
                </a>
            </div>

            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
                <div class="flex items-center justify-between gap-sm">
                    <p class="text-xs font-bold text-brand-forest uppercase">{{ __('parametres.section_logo') }}</p>
                    @if($this->settings->logo_path)
                        <button type="button" wire:click="supprimerFichier('logo')" wire:confirm="{{ __('parametres.confirm_supprimer_logo') }}" class="h-8 px-sm border border-error-deep/40 text-error-deep rounded-lg text-[11px] font-bold hover:bg-error-bg flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">delete</span>{{ __('parametres.btn_supprimer') }}</button>
                    @endif
                </div>
                {{-- CONF-1 : glisser-déposer par directives Alpine `x-on:` posées dans la vue (aucun script à part) ; un fichier déposé passe par le même `<input>` que le clic. --}}
                <label x-data="{ survol: false, apercu: null, deposer(e) { if (e.dataTransfer.files.length) { $refs.entree.files = e.dataTransfer.files; $refs.entree.dispatchEvent(new Event('change', { bubbles: true })); } } }"
                    x-on:dragover.prevent="survol = true" x-on:dragleave.prevent="survol = false" x-on:drop.prevent="survol = false; deposer($event)"
                    :class="survol ? 'border-brand-emerald bg-surface-zebra' : 'border-outline-variant'"
                    class="border-2 border-dashed rounded-lg p-lg text-center hover:border-brand-emerald transition-colors cursor-pointer block">
                    <input x-ref="entree" x-on:change="apercu = $event.target.files.length ? URL.createObjectURL($event.target.files[0]) : null" wire:model="logoFile" type="file" accept=".png,.jpg,.jpeg,.webp,image/png,image/jpeg,image/webp" class="hidden">
                    @if($logoFile)
                        <img x-show="apercu" :src="apercu" class="h-12 mx-auto mb-xs object-contain" alt="Aperçu du fichier choisi">
                    @elseif($this->settings->logo_path)
                        <img src="{{ \App\Support\IdentiteVisuelle::logoUrl() }}" class="h-12 mx-auto mb-xs object-contain" alt="Logo actuel">
                    @endif
                    <span class="material-symbols-outlined text-outline-variant" style="font-size:40px;">add_photo_alternate</span>
                    <p class="text-xs text-outline mt-xs font-semibold">{{ $logoFile ? $logoFile->getClientOriginalName() : __('parametres.aide_upload_logo') }}</p>
                    <p class="text-[10px] text-outline mt-xs">{{ __('parametres.aide_format_logo') }}</p>
                </label>
                @error('logoFile') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
                <div class="flex items-center justify-between gap-sm">
                    <p class="text-xs font-bold text-brand-forest uppercase">{{ __('parametres.section_favicon') }}</p>
                    @if($this->settings->favicon_path)
                        <button type="button" wire:click="supprimerFichier('favicon')" wire:confirm="{{ __('parametres.confirm_supprimer_favicon') }}" class="h-8 px-sm border border-error-deep/40 text-error-deep rounded-lg text-[11px] font-bold hover:bg-error-bg flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">delete</span>{{ __('parametres.btn_supprimer') }}</button>
                    @endif
                </div>
                {{-- CONF-1 : glisser-déposer par directives Alpine `x-on:` posées dans la vue (aucun script à part) ; un fichier déposé passe par le même `<input>` que le clic. --}}
                <label x-data="{ survol: false, apercu: null, deposer(e) { if (e.dataTransfer.files.length) { $refs.entree.files = e.dataTransfer.files; $refs.entree.dispatchEvent(new Event('change', { bubbles: true })); } } }"
                    x-on:dragover.prevent="survol = true" x-on:dragleave.prevent="survol = false" x-on:drop.prevent="survol = false; deposer($event)"
                    :class="survol ? 'border-brand-emerald bg-surface-zebra' : 'border-outline-variant'"
                    class="border-2 border-dashed rounded-lg p-lg text-center hover:border-brand-emerald transition-colors cursor-pointer block">
                    <input x-ref="entree" x-on:change="apercu = $event.target.files.length ? URL.createObjectURL($event.target.files[0]) : null" wire:model="faviconFile" type="file" accept=".ico,.png,image/png,image/x-icon,image/vnd.microsoft.icon" class="hidden">
                    @if($faviconFile)
                        <img x-show="apercu" :src="apercu" class="h-8 mx-auto mb-xs object-contain" alt="Aperçu du fichier choisi">
                    @elseif($this->settings->favicon_path)
                        <img src="{{ \App\Support\IdentiteVisuelle::faviconUrl() }}" class="h-8 mx-auto mb-xs object-contain" alt="Favicon actuel">
                    @endif
                    <span class="material-symbols-outlined text-outline-variant" style="font-size:40px;">web</span>
                    <p class="text-xs text-outline mt-xs font-semibold">{{ $faviconFile ? $faviconFile->getClientOriginalName() : __('parametres.aide_upload_favicon') }}</p>
                    <p class="text-[10px] text-outline mt-xs">{{ __('parametres.aide_format_favicon') }}</p>
                </label>
                @error('faviconFile') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
        </div>

        <div class="bg-info-blue/10 border border-info-blue/20 rounded-lg p-sm mt-lg text-[11px] text-brand-forest" id="facturation-mecef">
            {{ __('parametres.info_facturation_emecef') }} <a wire:navigate href="{{ route('parametres.hub', ['tab' => 'facturation']) }}" class="font-bold underline">{{ __('parametres.onglet_facturation') }}</a>.
        </div>

        <div class="bg-white border border-outline-variant rounded-lg p-md mt-lg">
            <h3 class="text-sm font-bold text-brand-forest mb-md flex items-center gap-xs">
                <span class="material-symbols-outlined text-[18px]">receipt_long</span>{{ __('parametres.section_regime_tva') }}
            </h3>

            <label class="flex items-start gap-sm cursor-pointer">
                <input type="checkbox" wire:model.live="tvaEnabled" class="mt-1 accent-brand-emerald">
                <span>
                    <span class="text-sm font-bold text-brand-forest">{{ __('parametres.label_assujettie_tva') }}</span>
                    <span class="block text-[11px] text-outline mt-xs">{{ __('parametres.aide_tva_detail') }}</span>
                </span>
            </label>
        </div>

        <div class="bg-white border border-outline-variant rounded-lg p-md mt-lg">
            <h3 class="text-sm font-bold text-brand-forest mb-xs flex items-center gap-xs">
                <span class="material-symbols-outlined text-[18px]">groups</span>{{ __('parametres.section_charges_sociales') }}
            </h3>
            <p class="text-[11px] text-outline mb-md">{{ __('parametres.desc_charges_sociales') }}</p>

            <a wire:navigate href="{{ route('parametres.bareme-its') }}" class="flex items-center gap-sm p-md mb-md rounded-lg border border-outline-variant hover:border-brand-emerald transition-all group">
                <span class="material-symbols-outlined text-brand-emerald text-[22px]">functions</span>
                <span class="flex-1">
                    <span class="block text-xs font-bold text-brand-forest">{{ __('parametres.lien_bareme_its_titre') }}</span>
                    <span class="block text-[11px] text-outline">{{ __('parametres.lien_bareme_its_detail') }}</span>
                </span>
                <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all">chevron_right</span>
            </a>

            @if($this->settings->payrollSettingsLocked() && ! $this->settings->payrollSettingsEditableBy(auth()->user()))
                <div class="bg-error-bg border border-error-deep/30 rounded-lg p-md mb-md flex items-start gap-sm">
                    <span class="material-symbols-outlined text-error-deep text-[20px]">lock</span>
                    <p class="text-[11px] text-error-deep">
                        Ces taux ont été arrêtés le {{ $this->settings->payroll_settings_edited_at?->format('d/m/Y à H:i') }}.
                        <strong>Seul un administrateur peut désormais les modifier</strong> — ils déterminent le net versé à chaque salarié et les montants déclarés aux organismes.
                    </p>
                </div>
            @endif

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_cnss_salariale') }}</label>
                    <input type="number" step="0.1" min="0" wire:model="cnssEmployeeRate" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    <p class="text-[10px] text-outline mt-xs">{{ __('parametres.aide_cnss_salariale') }}</p>
                    @error('cnssEmployeeRate') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_vps') }}</label>
                    <input type="number" step="0.1" min="0" wire:model="vpsRate" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    <p class="text-[10px] text-outline mt-xs">
                        Charge patronale sur le brut, sans plafond. <strong>2 %</strong> pour les structures privées d'enseignement,
                        <strong>4 %</strong> pour les autres — cette exploitation étant une ferme école, le taux applicable est à confirmer auprès de la DGI.
                    </p>
                    @error('vpsRate') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_cnss_patronale_pensions') }}</label>
                    <input type="number" step="0.1" min="0" wire:model="cnssEmployerPensionRate" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    @error('cnssEmployerPensionRate') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_cnss_patronale_famille') }}</label>
                    <input type="number" step="0.1" min="0" wire:model="cnssEmployerFamilyRate" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    @error('cnssEmployerFamilyRate') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_cnss_patronale_risques') }}</label>
                    <input type="number" step="0.1" min="1" max="4" wire:model="cnssEmployerRiskRate" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    <p class="text-[10px] text-outline mt-xs">{{ __('parametres.aide_cnss_risques') }}</p>
                    @error('cnssEmployerRiskRate') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
            </div>
        </div>

        <button type="submit" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm px-lg py-sm rounded-full transition-all mt-lg">
            <span class="material-symbols-outlined text-[18px]">save</span>{{ __('parametres.btn_enregistrer_modifs') }}
        </button>
    </form>
</div>
