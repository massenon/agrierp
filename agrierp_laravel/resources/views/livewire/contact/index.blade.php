<div x-data="{ tab: 'message' }">
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">support_agent</span>Contactez l'Éditeur
        </h2>
        <p class="text-xs text-outline mt-xs">Assistance technique, suggestions et signalement d'anomalies pour AgriERP.</p>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-[60%_40%] gap-md">
        <div class="bg-white border border-outline-variant rounded-lg p-md">
            <div class="flex items-center gap-xs border-b border-outline-variant mb-md overflow-x-auto">
                <button type="button" @click="tab = 'message'" :class="tab === 'message' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline'" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap">Envoyer un Message</button>
                <button type="button" @click="tab = 'bug'" :class="tab === 'bug' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline'" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap">Signaler un Bug</button>
            </div>

            <form wire:submit="sendMessage" x-show="tab === 'message'" class="space-y-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Objet *</label>
                    <input wire:model="subject" type="text" placeholder="ex : Question sur le module Comptabilité" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('subject') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('subject') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Message *</label>
                    <textarea wire:model="message" rows="6" placeholder="Décrivez votre question ou suggestion..." class="w-full px-md py-sm border rounded-lg text-sm {{ $errors->has('message') ? 'is-invalid' : 'border-outline-variant' }}"></textarea>
                    @error('message') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <button type="submit" wire:loading.attr="disabled" wire:target="sendMessage" class="px-lg py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest disabled:opacity-50 text-white font-bold text-sm flex items-center gap-xs">
                    <span class="material-symbols-outlined text-[18px]" wire:loading.remove wire:target="sendMessage">send</span>
                    <span class="material-symbols-outlined text-[18px] animate-spin" wire:loading wire:target="sendMessage">progress_activity</span>
                    Envoyer le Message
                </button>
            </form>

            <form wire:submit="reportBug" x-show="tab === 'bug'" x-cloak class="space-y-md" enctype="multipart/form-data">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Module Concerné *</label>
                    <select wire:model="module" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('module') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">-- Sélectionner --</option>
                        @foreach($moduleOptions as $option)
                            <option value="{{ $option }}">{{ $option }}</option>
                        @endforeach
                    </select>
                    @error('module') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Description du Problème *</label>
                    <textarea wire:model="description" rows="4" placeholder="Que s'est-il passé ? Que attendiez-vous ?" class="w-full px-md py-sm border rounded-lg text-sm {{ $errors->has('description') ? 'is-invalid' : 'border-outline-variant' }}"></textarea>
                    @error('description') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Étapes pour Reproduire</label>
                    <textarea wire:model="steps" rows="3" placeholder="1. Aller dans... 2. Cliquer sur..." class="w-full px-md py-sm border border-outline-variant rounded-lg text-sm"></textarea>
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Capture d'Écran (optionnel)</label>
                    <label for="screenshot-input" class="block border-2 border-dashed rounded-lg p-lg text-center cursor-pointer {{ $errors->has('screenshot') ? 'border-error-red' : 'border-outline-variant' }}">
                        <input wire:model="screenshot" id="screenshot-input" type="file" accept="image/*" class="hidden">
                        <span class="material-symbols-outlined text-outline-variant" style="font-size:36px;">add_a_photo</span>
                        <p class="text-xs text-outline mt-xs font-semibold" wire:loading.remove wire:target="screenshot">
                            {{ $screenshot ? $screenshot->getClientOriginalName() : 'Joindre une capture d\'écran' }}
                        </p>
                        <p class="text-xs text-outline mt-xs font-semibold" wire:loading wire:target="screenshot">Chargement…</p>
                    </label>
                    @error('screenshot') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <button type="submit" wire:loading.attr="disabled" wire:target="reportBug" class="px-lg py-sm rounded-lg bg-error-red hover:bg-red-800 disabled:opacity-50 text-white font-bold text-sm flex items-center gap-xs">
                    <span class="material-symbols-outlined text-[18px]" wire:loading.remove wire:target="reportBug">bug_report</span>
                    <span class="material-symbols-outlined text-[18px] animate-spin" wire:loading wire:target="reportBug">progress_activity</span>
                    Signaler le Bug
                </button>
            </form>
        </div>

        <div class="space-y-md">
            <div class="bg-white border border-outline-variant rounded-lg p-md">
                <p class="text-xs font-bold text-brand-forest uppercase mb-md">Coordonnées de l'Éditeur</p>
                <div class="space-y-sm text-xs">
                    <div class="flex items-start gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">person</span><span><strong class="text-brand-forest">Dr MASSENON Rhodes</strong><br><span class="text-outline">Docteur en Génie Logiciel et IA</span></span></div>
                    <div class="flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">mail</span><a href="mailto:rarhodes06@gmail.com" class="hover:underline">rarhodes06@gmail.com</a></div>
                    <div class="flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">alternate_email</span><a href="mailto:contact@massenonrhodes.com" class="hover:underline">contact@massenonrhodes.com</a></div>
                    <div class="flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">call</span>+229 01 51 33 50 40</div>
                    <div class="flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">smartphone</span>+229 01 97 31 24 37</div>
                    <div class="flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">schedule</span>Lun-Ven, 8h-17h (GMT)</div>
                </div>
            </div>
            {{-- Ticket 15.8 — ORIENTER VERS LE BON INTERLOCUTEUR.
                 Un barème fiscal ou un taux de charges ne se corrige pas dans
                 le code : c'est le cabinet qui accompagne la ferme dans le
                 cadre du PAEB qui les valide. Sans ce rappel, ces demandes
                 arrivent à l'éditeur, qui ne peut que les réorienter. --}}
            <div class="bg-white border border-outline-variant rounded-lg p-md">
                <p class="text-xs font-bold text-brand-forest uppercase mb-sm">Qui contacter ?</p>
                <div class="space-y-sm text-xs text-outline">
                    <div class="flex items-start gap-xs">
                        <span class="material-symbols-outlined text-brand-emerald text-[18px]">bug_report</span>
                        <span><strong class="text-brand-forest">Le logiciel se comporte mal</strong><br>Anomalie, question d'utilisation, évolution : utilisez le formulaire ci-contre.</span>
                    </div>
                    <div class="flex items-start gap-xs">
                        <span class="material-symbols-outlined text-brand-emerald text-[18px]">balance</span>
                        <span><strong class="text-brand-forest">Un chiffre réglementaire à valider</strong><br>Barème IR-PTS / ITS, taux CNSS, plan comptable : adressez-vous au <strong class="text-brand-forest">Cabinet FAGUEZ SARL</strong>, cabinet d'accompagnement des PME du projet PAEB.</span>
                    </div>
                </div>
            </div>
            <div class="bg-info-blue/10 border border-info-blue/30 rounded-lg p-md">
                <p class="text-xs font-bold text-brand-forest mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[18px] text-info-blue">lightbulb</span>Avant de nous contacter</p>
                <p class="text-xs text-outline">Consultez d'abord notre <a wire:navigate href="/aide-a-propos" class="text-brand-emerald font-bold hover:underline">Aide &amp; FAQ</a> - la réponse à votre question s'y trouve peut-être déjà.</p>
            </div>
        </div>
    </div>
</div>
