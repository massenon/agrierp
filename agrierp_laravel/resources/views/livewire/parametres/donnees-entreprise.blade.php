<div class="mt-md">
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">domain</span>Données de l'Entreprise
        </h2>
        <p class="text-xs text-outline mt-xs">Identité légale, fiscale et configuration technique de la Ferme École OLOUWACHEGOUN.</p>
    </div>

    <form wire:submit="save" class="space-y-md">
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-md">
            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
                <p class="text-xs font-bold text-brand-forest uppercase">Informations Générales</p>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Raison Sociale *</label>
                    <input wire:model="companyName" type="text" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('companyName') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('companyName') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nom du Promoteur</label>
                    <input wire:model="promoterName" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Adresse du Siège d'Exploitation</label>
                    <input wire:model="address" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <div class="grid grid-cols-2 gap-sm">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Téléphone Principal</label>
                        <input wire:model="phone" type="tel" placeholder="+229 XX XX XX XX" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Email de Contact</label>
                        <input wire:model="email" type="email" placeholder="contact@fermeolouwachegoun.com" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('email') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('email') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                </div>
            </div>

            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
                <p class="text-xs font-bold text-brand-forest uppercase">Informations Légales &amp; Fiscales</p>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Identifiant Fiscal Unique (IFU) *</label>
                    <input wire:model="ifu" type="text" inputmode="numeric" placeholder="ex : 3202601234567" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('ifu') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('ifu') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Registre du Commerce (RCCM)</label>
                    <input wire:model="rccm" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <div class="bg-info-blue/10 border border-info-blue/20 rounded-lg p-sm text-[10px] text-brand-forest">Ces informations apparaissent sur toutes les factures normalisées MeCeF et les documents officiels générés par LogiAgriERP.</div>
            </div>

            {{-- Ticket CFG-1 — la configuration SMTP a UNE seule saisie : l'onglet « Email (SMTP) » de ce hub. --}}
            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md lg:col-span-2">
                <p class="text-xs font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">mail</span>Configuration Email (SMTP)</p>
                <a wire:navigate href="{{ route('parametres.hub', ['tab' => 'email']) }}" class="flex items-center gap-sm p-md rounded-lg border border-outline-variant hover:border-brand-emerald transition-all group">
                    <span class="material-symbols-outlined text-brand-emerald text-[22px]">settings_input_antenna</span>
                    <span class="flex-1">
                        <span class="block text-xs font-bold text-brand-forest">Serveur d'envoi, mot de passe et e-mail de test</span>
                        <span class="block text-[11px] text-outline">Se règlent dans l'onglet Email (SMTP) — une seule configuration pour toute l'application.</span>
                    </span>
                    <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all">chevron_right</span>
                </a>
            </div>

            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
                <div class="flex items-center justify-between gap-sm">
                    <p class="text-xs font-bold text-brand-forest uppercase">Logo de l'Entreprise</p>
                    @if($this->settings->logo_path)
                        <button type="button" wire:click="supprimerFichier('logo')" wire:confirm="Supprimer le logo de l'entreprise ? Le fichier sera effacé." class="h-8 px-sm border border-error-deep/40 text-error-deep rounded-lg text-[11px] font-bold hover:bg-error-bg flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">delete</span>Supprimer</button>
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
                    <p class="text-xs text-outline mt-xs font-semibold">{{ $logoFile ? $logoFile->getClientOriginalName() : 'Glisser-déposer ou cliquer pour choisir un logo' }}</p>
                    <p class="text-[10px] text-outline mt-xs">PNG carré, fond transparent recommandé, max 2 Mo</p>
                </label>
                @error('logoFile') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
                <div class="flex items-center justify-between gap-sm">
                    <p class="text-xs font-bold text-brand-forest uppercase">Favicon (Icône d'Onglet)</p>
                    @if($this->settings->favicon_path)
                        <button type="button" wire:click="supprimerFichier('favicon')" wire:confirm="Supprimer l'icône du site de l'entreprise ? Le fichier sera effacé." class="h-8 px-sm border border-error-deep/40 text-error-deep rounded-lg text-[11px] font-bold hover:bg-error-bg flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">delete</span>Supprimer</button>
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
                    <p class="text-xs text-outline mt-xs font-semibold">{{ $faviconFile ? $faviconFile->getClientOriginalName() : 'Glisser-déposer ou cliquer pour choisir un favicon' }}</p>
                    <p class="text-[10px] text-outline mt-xs">ICO ou PNG 32x32px, max 500 Ko</p>
                </label>
                @error('faviconFile') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
        </div>

        <div class="bg-info-blue/10 border border-info-blue/20 rounded-lg p-sm mt-lg text-[11px] text-brand-forest" id="facturation-mecef">
            Le mode de facturation normalisée, le jeton et l'adresse de l'API e-MECeF se règlent dans l'onglet <a wire:navigate href="{{ route('parametres.hub', ['tab' => 'facturation']) }}" class="font-bold underline">Facturation normalisée (e-MECeF)</a>.
        </div>

        <div class="bg-white border border-outline-variant rounded-lg p-md mt-lg">
            <h3 class="text-sm font-bold text-brand-forest mb-md flex items-center gap-xs">
                <span class="material-symbols-outlined text-[18px]">receipt_long</span>Régime de TVA
            </h3>

            <label class="flex items-start gap-sm cursor-pointer">
                <input type="checkbox" wire:model.live="tvaEnabled" class="mt-1 accent-brand-emerald">
                <span>
                    <span class="text-sm font-bold text-brand-forest">Exploitation assujettie à la TVA</span>
                    <span class="block text-[11px] text-outline mt-xs">
                        Activé : les rubriques de TVA apparaissent et les montants sont présentés <strong>TTC</strong> ; les écritures ventilent la taxe (443 collectée, 445 déductible).
                        Désactivé : aucune rubrique de TVA, les montants sont des montants <strong>HT</strong>, et aucune ligne de taxe n'est comptabilisée.
                        Le taux porté par chaque produit reste conservé au catalogue — rien n'est à ressaisir le jour où l'exploitation devient assujettie.
                    </span>
                </span>
            </label>
        </div>

        <div class="bg-white border border-outline-variant rounded-lg p-md mt-lg">
            <h3 class="text-sm font-bold text-brand-forest mb-xs flex items-center gap-xs">
                <span class="material-symbols-outlined text-[18px]">groups</span>Charges sociales et fiscales sur salaires
            </h3>
            <p class="text-[11px] text-outline mb-md">
                Retenues <strong>salariales</strong> (prélevées sur le salarié, diminuent son net) et charges <strong>patronales</strong>
                (versées en plus par l'employeur, sans toucher au net).
            </p>

            <a wire:navigate href="{{ route('parametres.bareme-its') }}" class="flex items-center gap-sm p-md mb-md rounded-lg border border-outline-variant hover:border-brand-emerald transition-all group">
                <span class="material-symbols-outlined text-brand-emerald text-[22px]">functions</span>
                <span class="flex-1">
                    <span class="block text-xs font-bold text-brand-forest">Barème IR-PTS / ITS — tranches d'imposition</span>
                    <span class="block text-[11px] text-outline">Progressif sur le net imposable, avec simulation immédiate du net à payer.</span>
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
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">CNSS salariale (%)</label>
                    <input type="number" step="0.1" min="0" wire:model="cnssEmployeeRate" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    <p class="text-[10px] text-outline mt-xs">Retenue sur le salarié — 3,6 % (branche pensions).</p>
                    @error('cnssEmployeeRate') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">VPS — Versement Patronal sur Salaires (%)</label>
                    <input type="number" step="0.1" min="0" wire:model="vpsRate" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    <p class="text-[10px] text-outline mt-xs">
                        Charge patronale sur le brut, sans plafond. <strong>2 %</strong> pour les structures privées d'enseignement,
                        <strong>4 %</strong> pour les autres — cette exploitation étant une ferme école, le taux applicable est à confirmer auprès de la DGI.
                    </p>
                    @error('vpsRate') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">CNSS patronale — pensions (%)</label>
                    <input type="number" step="0.1" min="0" wire:model="cnssEmployerPensionRate" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    @error('cnssEmployerPensionRate') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">CNSS patronale — prestations familiales (%)</label>
                    <input type="number" step="0.1" min="0" wire:model="cnssEmployerFamilyRate" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    @error('cnssEmployerFamilyRate') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">CNSS patronale — risques professionnels (%)</label>
                    <input type="number" step="0.1" min="1" max="4" wire:model="cnssEmployerRiskRate" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    <p class="text-[10px] text-outline mt-xs">De 1 à 4 % selon le niveau de risque de l'entreprise.</p>
                    @error('cnssEmployerRiskRate') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
            </div>
        </div>

        <button type="submit" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm px-lg py-sm rounded-full transition-all mt-lg">
            <span class="material-symbols-outlined text-[18px]">save</span>Enregistrer les Modifications
        </button>
    </form>
</div>
