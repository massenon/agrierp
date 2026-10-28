<div class="min-h-screen w-full flex items-center justify-center bg-surface-bg p-md">
    <div class="w-full max-w-[440px] bg-white rounded-lg border border-outline-variant shadow-sm p-lg space-y-5">
        <div class="flex flex-col items-center text-center gap-1">
            <span class="material-symbols-outlined text-brand-emerald" style="font-size:38px;">lock_reset</span>
            <span class="text-[22px] font-black text-brand-forest tracking-tight">Agri<span class="text-brand-maize-ink">ERP</span></span>
            <h3 class="text-brand-forest text-lg font-bold leading-tight mt-xs">Réinitialiser le mot de passe</h3>
            <p class="text-outline text-xs">Choisissez un nouveau mot de passe pour votre compte.</p>
        </div>

        <form wire:submit="submit" class="space-y-4" novalidate>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold tracking-wider mb-1" for="email">ADRESSE E-MAIL</label>
                <input wire:model="email" id="email" type="email" class="w-full px-4 py-2.5 border rounded-lg focus:ring-2 focus:ring-brand-emerald outline-none text-xs h-11 {{ $errors->has('email') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('email') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold tracking-wider mb-1" for="password">NOUVEAU MOT DE PASSE</label>
                <input wire:model="password" id="password" type="password" class="w-full px-4 py-2.5 border rounded-lg focus:ring-2 focus:ring-brand-emerald outline-none text-xs h-11 {{ $errors->has('password') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('password') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold tracking-wider mb-1" for="password_confirmation">CONFIRMER LE MOT DE PASSE</label>
                <input wire:model="password_confirmation" id="password_confirmation" type="password" class="w-full px-4 py-2.5 border border-outline-variant rounded-lg focus:ring-2 focus:ring-brand-emerald outline-none text-xs h-11">
            </div>
            <button type="submit" class="w-full bg-brand-emerald hover:bg-brand-forest text-white font-bold h-11 rounded-lg shadow-sm active:scale-[0.98] transition-all flex items-center justify-center gap-2 text-xs uppercase tracking-wider">
                <span class="material-symbols-outlined text-[16px]">lock_reset</span><span>Réinitialiser le mot de passe</span>
            </button>
        </form>

        <div class="text-center">
            <a wire:navigate href="/login" class="text-xs font-semibold text-brand-emerald hover:underline">← Retour à la connexion</a>
        </div>
    </div>
</div>
