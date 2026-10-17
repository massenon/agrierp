<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">settings_input_antenna</span>Intégrations &amp; Notifications
        </h2>
        <p class="text-xs text-outline mt-xs">Configuration réelle des canaux de communication sortants (Email SMTP, SMS).</p>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-md">
        <div class="bg-white border border-outline-variant rounded-lg p-lg space-y-md">
            <h3 class="text-sm font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">mail</span>Email — Serveur SMTP</h3>
            <form wire:submit="saveSmtp" class="space-y-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Hôte SMTP *</label>
                    <input wire:model="smtpHost" type="text" placeholder="ex : smtp.gmail.com" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('smtpHost') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('smtpHost') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div class="grid grid-cols-2 gap-sm">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Port *</label>
                        <input wire:model="smtpPort" type="number" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('smtpPort') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('smtpPort') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Sécurité</label>
                        <select wire:model="smtpSecurity" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                            <option value="tls">TLS</option>
                            <option value="ssl">SSL</option>
                            <option value="">Aucune</option>
                        </select>
                    </div>
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Identifiant SMTP</label>
                    <input wire:model="smtpUser" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Mot de Passe SMTP</label>
                    <input wire:model="smtpPassword" type="password" placeholder="Laisser vide pour conserver le mot de passe actuel" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    <p class="text-[10px] text-outline mt-xs">Chiffré en base — jamais réaffiché en clair une fois enregistré.</p>
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Adresse d'Expédition</label>
                    <input wire:model="fromEmail" type="email" placeholder="ex : contact@ferme-olouwachegoun.bj" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('fromEmail') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('fromEmail') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <button type="submit" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm">Enregistrer la Configuration SMTP</button>
            </form>

            <div class="border-t border-outline-variant pt-md flex items-center gap-xs">
                <input wire:model="testEmailTo" type="email" placeholder="Envoyer un email de test à..." class="flex-1 h-10 px-md border border-outline-variant rounded-lg text-xs">
                <button type="button" wire:click="sendTestEmail" class="px-md py-2 rounded-lg border border-outline-variant text-xs font-bold text-brand-forest hover:bg-surface-zebra whitespace-nowrap">Tester</button>
            </div>
        </div>

        <div class="bg-white border border-outline-variant rounded-lg p-lg space-y-md">
            <h3 class="text-sm font-bold text-brand-forest uppercase flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">sms</span>SMS — Fournisseur API</h3>
            <form wire:submit="saveSms" class="space-y-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Fournisseur *</label>
                    <select wire:model.live="smsProvider" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('smsProvider') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">-- Sélectionner --</option>
                        <option value="twilio">Twilio</option>
                        <option value="vonage">Vonage</option>
                    </select>
                    @error('smsProvider') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>

                @if($smsProvider === 'twilio')
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Account SID</label>
                        <input wire:model="twilioSid" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm font-mono">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Auth Token</label>
                        <input wire:model="twilioToken" type="password" placeholder="Laisser vide pour conserver le token actuel" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Numéro d'Envoi</label>
                        <input wire:model="twilioFrom" type="text" placeholder="ex : +14155238886" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                @elseif($smsProvider === 'vonage')
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">API Key</label>
                        <input wire:model="vonageKey" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm font-mono">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">API Secret</label>
                        <input wire:model="vonageSecret" type="password" placeholder="Laisser vide pour conserver le secret actuel" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nom d'Expéditeur</label>
                        <input wire:model="vonageFrom" type="text" placeholder="ex : AgriERP" maxlength="11" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                @endif

                <button type="submit" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm">Enregistrer la Configuration SMS</button>
            </form>

            @if($smsProvider)
                <div class="border-t border-outline-variant pt-md flex items-center gap-xs">
                    <input wire:model="testSmsTo" type="text" placeholder="Envoyer un SMS de test à... (ex : +22996456789)" class="flex-1 h-10 px-md border border-outline-variant rounded-lg text-xs">
                    <button type="button" wire:click="sendTestSms" class="px-md py-2 rounded-lg border border-outline-variant text-xs font-bold text-brand-forest hover:bg-surface-zebra whitespace-nowrap">Tester</button>
                </div>
            @endif

            <div class="bg-surface-zebra rounded-lg p-sm text-[11px] text-outline">
                WhatsApp ne nécessite aucune configuration ici : les relances WhatsApp s'ouvrent directement via un lien <code>wa.me</code> vers le numéro du client, sans passerelle tierce.
            </div>
        </div>
    </div>
</div>
