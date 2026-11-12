<div class="mt-md space-y-lg">
    <div class="border-b border-outline-variant pb-md">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-error-deep text-[26px]">settings_backup_restore</span>{{ __('parametres.titre_reinitialisation') }}
        </h2>
        <p class="text-xs text-outline mt-xs">{{ __('parametres.desc_reinitialisation') }}</p>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md">
        <h3 class="font-bold text-sm text-brand-forest mb-sm flex items-center gap-xs"><span class="material-symbols-outlined text-info-blue text-[18px]">data_object</span>{{ __('parametres.section_mode_demo') }}</h3>
        <p class="text-xs text-outline mb-md">{{ __('parametres.desc_mode_demo') }}</p>
        <label class="relative inline-flex items-center cursor-pointer gap-sm">
            <input type="checkbox" wire:click="basculerModeDemo" {{ $this->modeDemoActif ? 'checked' : '' }} class="sr-only peer">
            <div class="w-11 h-6 bg-outline-variant rounded-full peer peer-checked:bg-brand-emerald transition-all"></div>
            <div class="absolute left-1 top-1 w-4 h-4 bg-white rounded-full transition-all peer-checked:translate-x-5"></div>
            <span class="text-xs font-bold text-brand-forest ml-2">{{ $this->modeDemoActif ? __('parametres.mode_demo_actif') : __('parametres.mode_demo_inactif') }}</span>
        </label>
    </div>

    @if($this->reinitVerrouillee)
        <div class="bg-error-bg border border-error-deep/30 rounded-lg p-md text-sm text-error-deep flex items-start gap-sm">
            <span class="material-symbols-outlined text-[20px] flex-shrink-0">lock</span>
            <div>
                <p class="font-bold">{{ __('parametres.reinit_verrouillee') }}</p>
                <p class="text-xs mt-xs">{{ __('parametres.reinit_verrouilee_aide') }}</p>
            </div>
        </div>
    @else
        <div class="bg-error-bg border border-error-deep/30 rounded-lg p-md space-y-sm">
            <h3 class="font-bold text-error-deep flex items-center gap-xs"><span class="material-symbols-outlined text-[20px]">warning</span>{{ __('parametres.titre_reinit_danger') }}</h3>
            <p class="text-xs text-error-deep">{{ __('parametres.desc_reinit_danger') }}</p>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-sm mt-sm">
                <div class="bg-error-bg/60 rounded p-sm text-xs space-y-1">
                    <p class="font-bold text-error-deep">{{ __('parametres.section_supprime') }}</p>
                    <ul class="list-disc pl-4 text-error-deep space-y-0.5">
                        @foreach($this->listeSupprimes as $item)
                            <li>{{ $item }}</li>
                        @endforeach
                    </ul>
                    <p class="text-[10px] text-outline mt-xs">{{ __('parametres.texte_supprime') }}</p>
                    <p class="text-[10px] text-outline">{{ __('parametres.texte_postes_reinit') }}</p>
                </div>
                <div class="bg-brand-emerald/5 border border-brand-emerald/20 rounded p-sm text-xs space-y-1">
                    <p class="font-bold text-brand-forest">{{ __('parametres.section_conserve') }}</p>
                    <ul class="list-disc pl-4 text-brand-forest space-y-0.5">
                        @foreach($this->listeConserves as $item)
                            <li>{{ $item }}</li>
                        @endforeach
                    </ul>
                    <p class="text-[10px] text-outline mt-xs">{{ __('parametres.texte_conserve') }}</p>
                </div>
            </div>
            <button type="button" x-on:click="$dispatch('open-modal', { name: 'modal-confirm-reinit' })" class="mt-md flex items-center gap-xs bg-error-deep hover:bg-red-800 text-white font-bold text-sm px-lg py-sm rounded-full">
                <span class="material-symbols-outlined text-[18px]">warning</span>{{ __('parametres.btn_reinitialiser_donnees') }}
            </button>
        </div>
    @endif

    <x-modal name="modal-confirm-reinit" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-error-deep flex items-center gap-xs"><span class="material-symbols-outlined">warning</span>{{ __('parametres.titre_modal_reinit') }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-confirm-reinit' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <p class="text-sm text-outline mb-md">{{ __('parametres.desc_modal_reinit') }}</p>
        <div>
            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_saisir_reinit') }}</label>
            <input wire:model="confirmText" type="text" placeholder="RÉINITIALISER" class="w-full h-11 px-md border {{ $errors->has('confirmText') ? 'border-error-deep' : 'border-outline-variant' }} rounded-lg text-sm">
            @error('confirmText') <p class="text-[11px] text-error-deep mt-xs">{{ $message }}</p> @enderror
        </div>
        <div class="flex justify-end gap-sm border-t border-outline-variant pt-md mt-md">
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-confirm-reinit' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('parametres.btn_annuler') }}</button>
            <button type="button" wire:click="reinitialiser" class="px-md py-sm rounded-lg bg-error-deep text-white text-sm font-bold hover:bg-red-800">{{ __('parametres.btn_confirmer_reinit') }}</button>
        </div>
    </x-modal>
</div>
