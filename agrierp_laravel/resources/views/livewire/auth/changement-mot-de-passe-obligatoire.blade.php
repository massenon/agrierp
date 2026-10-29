<div class="min-h-screen w-full flex items-center justify-center bg-white p-6">
    <div class="w-full max-w-[440px] space-y-5">
        <div class="flex flex-col items-center text-center gap-1">
            <span class="material-symbols-outlined text-brand-emerald" style="font-size:38px;">lock_reset</span>
            <h2 class="text-brand-forest text-xl font-bold leading-tight">Changement de mot de passe obligatoire</h2>
            <p class="text-outline text-xs">Un administrateur vous a donné un mot de passe temporaire. Choisissez maintenant votre propre mot de passe pour accéder à l'application.</p>
        </div>

        <form wire:submit="updatePassword" class="space-y-4" novalidate>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold tracking-wider mb-1" for="current_password">MOT DE PASSE TEMPORAIRE</label>
                <input wire:model="current_password" id="current_password" type="password" autocomplete="current-password"
                    class="w-full px-4 py-2.5 border rounded-lg focus:ring-2 focus:ring-brand-emerald outline-none text-xs h-11 {{ $errors->has('current_password') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('current_password') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold tracking-wider mb-1" for="new_password">NOUVEAU MOT DE PASSE</label>
                <input wire:model="new_password" id="new_password" type="password" autocomplete="new-password" placeholder="Min. 8 caractères, 1 majuscule, 1 chiffre"
                    class="w-full px-4 py-2.5 border rounded-lg focus:ring-2 focus:ring-brand-emerald outline-none text-xs h-11 {{ $errors->has('new_password') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('new_password') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold tracking-wider mb-1" for="new_password_confirmation">CONFIRMER LE NOUVEAU MOT DE PASSE</label>
                <input wire:model="new_password_confirmation" id="new_password_confirmation" type="password" autocomplete="new-password"
                    class="w-full px-4 py-2.5 border border-outline-variant rounded-lg focus:ring-2 focus:ring-brand-emerald outline-none text-xs h-11">
            </div>
            <button type="submit" class="w-full bg-brand-emerald hover:bg-brand-forest text-white font-bold h-11 rounded-lg shadow-sm text-xs uppercase tracking-wider">Enregistrer le mot de passe</button>
        </form>

        <form method="POST" action="{{ route('logout') }}" class="text-center">
            @csrf
            <button type="submit" class="text-xs font-semibold text-outline hover:underline">Se déconnecter</button>
        </form>
    </div>

    <x-toast-container />
</div>
