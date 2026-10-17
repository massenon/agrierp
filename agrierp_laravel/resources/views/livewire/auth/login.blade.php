<div class="min-h-screen w-full flex flex-col lg:flex-row bg-white transition-colors duration-300">

    <aside class="relative hidden lg:flex lg:w-[50%] flex-col justify-between p-8 overflow-hidden" style="background: linear-gradient(180deg, rgba(5,46,22,0.10) 0%, rgba(0,33,13,0.55) 100%), url('{{ asset('assets/images/image_login.png') }}'); background-size: cover; background-position: center;">
        <div class="relative z-10 flex items-center gap-2">
            <span class="material-symbols-outlined text-accent-yellow" style="font-size:26px;">agriculture</span>
            <h1 class="text-white font-extrabold text-lg">Agri<span class="text-brand-maize">ERP</span></h1>
        </div>
        <div class="relative z-10 flex-1"></div>
        <div class="relative z-10 text-center space-y-1 border-t border-white/10 pt-4">
            <p class="text-white/70 text-[10px] uppercase tracking-widest font-bold">Projet d'Appui à l'Entrepreneuriat au Bénin (PAEB)</p>
            <p class="text-white/50 text-[10px] uppercase tracking-widest font-semibold">PAEB &nbsp;&middot;&nbsp; CABINET FAGUEZ SARL</p>
        </div>
    </aside>

    <main class="flex-1 flex flex-col justify-between p-6 lg:p-8 bg-white transition-colors duration-300">
        <div class="flex justify-end gap-2 items-center text-xs text-outline">
            <button type="button" @click="darkMode = !darkMode" class="flex items-center gap-1 px-3 py-1.5 border border-outline-variant hover:bg-surface-zebra rounded-full">
                <span class="material-symbols-outlined text-[16px]" x-text="darkMode ? 'light_mode' : 'dark_mode'"></span>
                <span class="hidden sm:inline" x-text="darkMode ? 'Mode clair' : 'Mode sombre'"></span>
            </button>
            <button type="button" class="flex items-center gap-1 px-3 py-1.5 border border-outline-variant hover:bg-surface-zebra rounded-full"><span class="material-symbols-outlined text-[16px]">translate</span><span class="hidden sm:inline">Français</span></button>
            <span class="font-bold tracking-wider px-2">v1.0.0</span>
        </div>

        <div class="my-auto mx-auto w-full max-w-[440px] space-y-5">
            <div class="flex flex-col items-center text-center gap-1">
                <div class="flex items-center gap-2">
                    <span class="material-symbols-outlined text-brand-emerald" style="font-size:38px;">agriculture</span>
                    <div class="flex flex-col items-start leading-none">
                        <span class="text-[22px] font-black text-brand-forest tracking-tight">Agri<span class="text-brand-maize-ink">ERP</span></span>
                        <span class="text-[9px] uppercase tracking-widest text-brand-emerald font-extrabold mt-0.5">Ferme Olouwachegoun</span>
                    </div>
                </div>
                <p class="text-[10px] text-brand-emerald font-bold uppercase tracking-[0.15em] border-t border-brand-emerald/10 pt-1 w-full">Votre logiciel de gestion intégrée</p>
            </div>

            <div class="grid grid-cols-7 gap-1 border-y border-outline-variant/40 py-3 text-center text-outline">
                <div><span class="material-symbols-outlined text-[16px]">local_florist</span></div>
                <div><span class="material-symbols-outlined text-[16px]">account_balance</span></div>
                <div><span class="material-symbols-outlined text-[16px]">point_of_sale</span></div>
                <div><span class="material-symbols-outlined text-[16px]">inventory_2</span></div>
                <div><span class="material-symbols-outlined text-[16px]">pets</span></div>
                <div><span class="material-symbols-outlined text-[16px]">analytics</span></div>
                <div><span class="material-symbols-outlined text-[16px]">settings</span></div>
            </div>

            <div>
                <h2 class="text-brand-forest text-xl font-bold leading-tight">Bienvenue !</h2>
                <p class="text-outline text-xs">Connectez-vous à votre espace d'administration AgriERP.</p>
            </div>

            @if($lockedSecondsRemaining !== null)
                <div
                    x-data="{ seconds: {{ $lockedSecondsRemaining }} }"
                    x-init="const t = setInterval(() => { if (seconds > 0) seconds--; else clearInterval(t); }, 1000)"
                    class="bg-error-bg border border-error-deep/30 text-error-deep text-xs rounded-lg px-4 py-2 flex items-center gap-2">
                    <span class="material-symbols-outlined text-[18px]">lock_clock</span>
                    <span>Trop de tentatives de connexion. Accès bloqué pendant <strong x-text="Math.floor(seconds/60) + 'min ' + (seconds%60) + 's'"></strong>.</span>
                </div>
            @endif

            <form wire:submit="submit" class="space-y-4" novalidate>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold tracking-wider mb-1" for="identifiant">NOM D'UTILISATEUR OU EMAIL</label>
                    <div class="relative">
                        <span class="material-symbols-outlined absolute left-4 top-1/2 -translate-y-1/2 text-outline text-[18px]">person</span>
                        <input wire:model="identifiant" id="identifiant" name="identifiant" autocomplete="username" type="text" placeholder="admin ou dg@olouwachegoun.bj"
                            class="w-full pl-11 pr-4 py-2.5 border rounded-lg focus:ring-2 focus:ring-brand-emerald outline-none text-xs h-11 {{ $errors->has('identifiant') ? 'is-invalid' : 'border-outline-variant' }}">
                    </div>
                    @error('identifiant') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold tracking-wider mb-1" for="password">MOT DE PASSE</label>
                    <div class="relative" x-data="{ visible: false }">
                        <span class="material-symbols-outlined absolute left-4 top-1/2 -translate-y-1/2 text-outline text-[18px]">lock</span>
                        <input wire:model="password" :type="visible ? 'text' : 'password'" id="password" name="password" autocomplete="current-password" placeholder="••••••••"
                            class="w-full pl-11 pr-11 py-2.5 border rounded-lg focus:ring-2 focus:ring-brand-emerald outline-none text-xs h-11 {{ $errors->has('password') ? 'is-invalid' : 'border-outline-variant' }}">
                        <button type="button" @click="visible = !visible" class="absolute right-4 top-1/2 -translate-y-1/2 text-outline hover:text-brand-forest">
                            <span class="material-symbols-outlined text-[18px]" x-text="visible ? 'visibility_off' : 'visibility'"></span>
                        </button>
                    </div>
                    @error('password') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div class="flex items-center justify-between text-xs">
                    <label class="flex items-center cursor-pointer">
                        <input wire:model="remember" type="checkbox" class="h-4 w-4 rounded border-outline-variant text-brand-emerald">
                        <span class="ml-2 text-outline">Se souvenir de moi</span>
                    </label>
                    <button type="button" x-on:click="$dispatch('open-modal', { name: 'forgot-password' })" class="font-semibold text-brand-emerald hover:underline">Mot de passe oublié ?</button>
                </div>
                <button type="submit" dusk="login-submit" @disabled($lockedSecondsRemaining !== null)
                    class="w-full bg-brand-emerald hover:bg-brand-forest disabled:opacity-50 text-white font-bold h-11 rounded-lg shadow-sm active:scale-[0.98] transition-all flex items-center justify-center gap-2 text-xs uppercase tracking-wider">
                    <span wire:loading.remove wire:target="submit" class="material-symbols-outlined text-[16px]">lock_open</span>
                    <span wire:loading wire:target="submit" class="material-symbols-outlined text-[16px] animate-spin">progress_activity</span>
                    <span>Se connecter</span>
                </button>
            </form>
        </div>

        <div class="border-t border-outline-variant/40 pt-4 flex items-center justify-center text-[10px] text-outline">
            <span>© {{ now()->year }} AgriERP — Projet d'Appui à l'Entrepreneuriat au Bénin (PAEB) — Accompagnement : Cabinet FAGUEZ SARL — Édité par Dr&nbsp;MASSENON&nbsp;Rhodes</span>
        </div>
    </main>

    <x-modal name="forgot-password" max-width="sm">
        <div class="flex items-center justify-between mb-4">
            <h3 class="font-bold text-lg text-brand-forest">Mot de passe oublié</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'forgot-password' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <p class="text-xs text-outline mb-4">Saisissez votre adresse e-mail professionnelle. Un lien de réinitialisation sécurisé vous sera envoyé.</p>
        <input wire:model="forgotEmail" type="email" placeholder="votre.email@olouwachegoun.bj" class="w-full h-11 px-4 border border-outline-variant rounded-lg text-xs mb-1 focus:ring-2 focus:ring-brand-emerald outline-none">
        @error('forgotEmail') <p class="invalid-feedback mb-3">{{ $message }}</p> @enderror
        <button type="button" wire:click="sendResetLink" class="w-full bg-brand-emerald hover:bg-brand-forest text-white font-bold h-11 rounded-lg text-xs uppercase tracking-wider mt-3">Envoyer le lien de réinitialisation</button>
    </x-modal>

    <x-toast-container />
</div>
