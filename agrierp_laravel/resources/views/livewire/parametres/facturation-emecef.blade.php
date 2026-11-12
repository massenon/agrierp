<div>
    <div class="mb-lg">
        <h2 class="text-xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">receipt_long</span>{{ __('parametres.titre_facturation_emecef') }}
        </h2>
        <p class="text-xs text-outline mt-xs">
            {{ __('parametres.desc_facturation_emecef') }}
        </p>
    </div>

    <form wire:submit="save" class="bg-white border border-outline-variant rounded-lg p-md space-y-md" id="facturation-mecef">
        <div class="bg-info-blue/10 border border-info-blue/20 rounded-lg p-sm text-[11px] text-brand-forest space-y-xs">
            <p class="font-bold">{{ __('parametres.info_ou_jeton') }}</p>
            <p>{{ __('parametres.aide_ou_jeton') }}</p>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
            <div class="sm:col-span-2">
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_mode_facturation') }}</label>
                <select wire:model.live="mecefMode" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                    @foreach(\App\Support\MecefMode::LIBELLES as $valeur => $libelle)
                        <option value="{{ $valeur }}">{{ $libelle }}</option>
                    @endforeach
                </select>
                @error('mecefMode') <p class="invalid-feedback">{{ $message }}</p> @enderror
                @if($mecefMode === 'boitier')
                    <p class="text-[10px] text-outline mt-xs">{{ __('parametres.aide_mode_boitier') }}</p>
                @elseif($mecefMode === 'desactive')
                    <p class="text-[10px] text-outline mt-xs">{{ __('parametres.aide_mode_desactive') }}</p>
                @else
                    <p class="text-[10px] text-outline mt-xs">{{ __('parametres.aide_mode_emecef') }}</p>
                @endif
            </div>

            <div class="sm:col-span-2">
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_ifu_emecef') }}</label>
                <input wire:model="ifu" type="text" inputmode="numeric" maxlength="13" placeholder="13 chiffres" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('ifu') ? 'is-invalid' : 'border-outline-variant' }}">
                <p class="text-[10px] text-outline mt-xs">{{ __('parametres.aide_ifu_emecef') }}</p>
                @error('ifu') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            @if($mecefMode === 'emecef')
                <div class="sm:col-span-2">
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_api_emecef') }}</label>
                    <input wire:model="mecefApiUrl" type="url" placeholder="https://…" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('mecefApiUrl') ? 'is-invalid' : 'border-outline-variant' }}">
                    <div class="flex flex-wrap gap-xs mt-xs">
                        @foreach(\App\Support\MecefMode::PREREGLAGES_URL as $cle => [$libellePreset, $adresse])
                            <button type="button" wire:click="choisirUrl('{{ $cle }}')" class="px-sm py-1 rounded-full border border-outline-variant text-[11px] font-bold text-brand-forest hover:bg-surface-zebra">{{ $libellePreset }}</button>
                        @endforeach
                    </div>
                    <p class="text-[10px] text-outline mt-xs">{{ __('parametres.aide_api_emecef') }}</p>
                    @error('mecefApiUrl') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>

                <div class="sm:col-span-2">
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_jeton_emecef') }}</label>
                    @if($this->jetonDeConfiguration && ! $remplacerJeton)
                        <div class="flex items-center gap-sm">
                            <span class="flex-1 h-11 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center text-outline">{{ __('parametres.jeton_dans_config') }}</span>
                            <button type="button" wire:click="$set('remplacerJeton', true)" class="px-md h-11 rounded-lg border border-outline-variant text-xs font-bold text-brand-forest hover:bg-surface-zebra">{{ __('parametres.btn_remplacer_jeton') }}</button>
                        </div>
                    @elseif($this->jetonConfigure && ! $remplacerJeton)
                        <div class="flex items-center gap-sm">
                            <span class="flex-1 h-11 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center tracking-widest">••••••••••••</span>
                            <button type="button" wire:click="$set('remplacerJeton', true)" class="px-md h-11 rounded-lg border border-outline-variant text-xs font-bold text-brand-forest hover:bg-surface-zebra">{{ __('parametres.btn_remplacer_jeton') }}</button>
                            <button type="button" wire:click="effacerJeton" wire:confirm="{{ __('parametres.confirm_effacer_jeton') }}" class="px-md h-11 rounded-lg border border-error-deep/40 text-xs font-bold text-error-deep hover:bg-error-bg">{{ __('parametres.btn_effacer_jeton') }}</button>
                        </div>
                    @else
                        <input wire:model="mecefJeton" type="password" autocomplete="off" placeholder="{{ __('parametres.aide_jeton_placeholder') }}" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    @endif
                    @error('mecefJeton') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>

                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_operateur_id') }}</label>
                    <input wire:model="mecefOperateurId" type="text" placeholder="{{ $this->repliOperateur['id'] }}" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_operateur_nom') }}</label>
                    <input wire:model="mecefOperateurNom" type="text" placeholder="{{ $this->repliOperateur['nom'] }}" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
            @endif
        </div>

        <div class="flex flex-wrap items-center justify-end gap-sm pt-sm border-t border-outline-variant">
            <button type="button" wire:click="tester" wire:loading.attr="disabled" wire:target="tester" dusk="tester-mecef" class="px-md py-sm rounded-lg border border-brand-emerald text-brand-emerald text-sm font-bold hover:bg-brand-emerald/5 disabled:opacity-50 flex items-center gap-xs">
                <span class="material-symbols-outlined text-[18px]">cloud_done</span>{{ __('parametres.btn_tester_config') }}
            </button>
            <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ __('parametres.btn_enregistrer') }}</button>
        </div>

        @if($resultatTest)
            <div class="rounded-lg border p-md space-y-xs {{ $resultatTest['ok'] ? 'border-brand-emerald/40 bg-brand-emerald/5' : 'border-error-deep/30 bg-error-bg' }}" id="resultat-test-mecef">
                <p class="text-sm font-bold {{ $resultatTest['ok'] ? 'text-brand-emerald' : 'text-error-deep' }} flex items-center gap-xs">
                    <span class="material-symbols-outlined text-[18px]">{{ $resultatTest['ok'] ? 'check_circle' : 'close' }}</span>{{ $resultatTest['resume'] }}
                </p>
                <ul class="text-[11px] text-brand-forest space-y-[2px]">
                    @foreach($resultatTest['lignes'] as $ligne)
                        <li><span class="font-bold">{{ $ligne['ok'] ? __('parametres.label_ok') : __('parametres.label_a_corriger') }}</span> — {{ $ligne['libelle'] }} : {{ $ligne['detail'] }}</li>
                    @endforeach
                </ul>
                <p class="text-[10px] text-outline">{{ __('parametres.info_test_mecef') }}</p>
            </div>
        @endif
    </form>
</div>
