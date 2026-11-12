<div class="mt-md">
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">account_balance_wallet</span>{{ __('parametres.titre_modes_paiement') }}
            </h2>
            <p class="text-xs text-outline mt-xs">{{ __('parametres.desc_modes_paiement') }}</p>
        </div>
        @can('manage-comptabilite')
            <button type="button" wire:click="openTransfer" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all">
                <span class="material-symbols-outlined text-[18px]">swap_horiz</span>{{ __('parametres.btn_virement_interne') }}
            </button>
        @endcan
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-3 gap-md mb-lg">
        <x-kpi-card :label="__('parametres.kpi_solde_caisse')" icon="payments" color="emerald" :value="number_format($this->kpis['caisse'], 0, ',', ' ').' F'" />
        <x-kpi-card :label="__('parametres.kpi_solde_banques')" icon="account_balance" color="blue" :value="number_format($this->kpis['banques'], 0, ',', ' ').' F'" />
        <x-kpi-card :label="__('parametres.kpi_solde_mobile_money')" icon="smartphone" color="maize" :value="number_format($this->kpis['mobile_money'], 0, ',', ' ').' F'" />
    </div>

    <div class="mb-lg">
        <div class="flex items-center justify-between mb-sm">
            <h3 class="text-sm font-bold text-brand-forest flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">payments</span>{{ __('parametres.section_caisse') }}</h3>
        </div>
        @foreach($this->caisseAccounts as $account)
            <div class="bg-white border border-outline-variant rounded-lg p-md flex items-center justify-between">
                <div>
                    <p class="text-sm font-bold text-brand-forest">{{ $account->label }}</p>
                    <p class="text-xs text-outline">Compte {{ $account->account_code }}</p>
                </div>
                <div class="text-right">
                    <p class="text-lg font-extrabold text-brand-emerald">{{ number_format($account->balance, 0, ',', ' ') }} FCFA</p>
                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[10px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">{{ __('parametres.statut_actif') }}</span>
                </div>
            </div>
        @endforeach
    </div>

    <div class="mb-lg">
        <div class="flex items-center justify-between mb-sm">
            <h3 class="text-sm font-bold text-brand-forest flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">account_balance</span>{{ __('parametres.section_banques') }}</h3>
            <button type="button" wire:click="openAddBank" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-[11px] px-md py-2 rounded-full"><span class="material-symbols-outlined text-[16px]">add_circle</span>{{ __('parametres.btn_ajouter_banque') }}</button>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-md">
            @forelse($this->bankAccounts as $account)
                <div class="bg-white border border-outline-variant rounded-lg p-md">
                    <div class="flex items-center justify-between mb-sm">
                        <p class="text-sm font-bold text-brand-forest">{{ $account->label }}</p>
                        <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[10px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">{{ __('parametres.statut_actif') }}</span>
                    </div>
                    <p class="text-xs text-outline">Titulaire : {{ $account->holder_name ?? '—' }}</p>
                    <p class="text-xs text-outline">RIB : {{ $account->rib }} - IBAN : {{ $account->iban }}</p>
                    <p class="text-lg font-extrabold text-brand-emerald mt-sm">{{ number_format($account->balance, 0, ',', ' ') }} FCFA</p>
                </div>
            @empty
                <p class="text-xs text-outline md:col-span-2">{{ __('parametres.msg_aucun_compte_bancaire') }}</p>
            @endforelse
        </div>
    </div>

    <div>
        <div class="flex items-center justify-between mb-sm">
            <h3 class="text-sm font-bold text-brand-forest flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">smartphone</span>{{ __('parametres.section_mobile_money') }}</h3>
            <button type="button" wire:click="openAddMomo" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-[11px] px-md py-2 rounded-full"><span class="material-symbols-outlined text-[16px]">add_circle</span>{{ __('parametres.btn_ajouter_momo') }}</button>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-md">
            @forelse($this->momoAccounts as $account)
                <div class="bg-white border border-outline-variant rounded-lg p-md">
                    <div class="flex items-center justify-between mb-sm">
                        <p class="text-sm font-bold text-brand-forest">{{ $account->label }}</p>
                        <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[10px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">{{ __('parametres.statut_actif') }}</span>
                    </div>
                    <p class="text-xs text-outline">Numéro : {{ $account->phone_number }} - Titulaire : {{ $account->holder_name ?? '—' }}</p>
                    <p class="text-lg font-extrabold text-brand-emerald mt-sm">{{ number_format($account->balance, 0, ',', ' ') }} FCFA</p>
                </div>
            @empty
                <p class="text-xs text-outline md:col-span-2">{{ __('parametres.msg_aucune_ligne_momo') }}</p>
            @endforelse
        </div>
    </div>

    <x-modal name="modal-add-bank" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ __('parametres.titre_ajouter_banque') }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-add-bank' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveBank" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_banque') }}</label>
                <select wire:model="bankName" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('bankName') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">{{ __('parametres.placeholder_selectionner') }}</option>
                    <option>BOA Bénin</option>
                    <option>Ecobank Bénin</option>
                    <option>UBA Bénin</option>
                    <option>NSIA Banque</option>
                </select>
                @error('bankName') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_titulaire') }}</label>
                <input wire:model="holderName" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_rib') }}</label>
                <input wire:model="rib" type="text" placeholder="BJ066 01001 ..." class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('rib') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('rib') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_iban') }}</label>
                <input wire:model="iban" type="text" placeholder="BJ66BJ..." class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('iban') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('iban') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_sous_compte') }}</label>
                <input wire:model="accountCode" type="text" placeholder="ex : 521103" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-add-bank' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('parametres.btn_annuler') }}</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ __('parametres.btn_enregistrer') }}</button>
            </div>
        </form>
    </x-modal>

    <x-modal name="modal-add-momo" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ __('parametres.titre_ajouter_momo') }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-add-momo' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveMomo" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_operateur') }}</label>
                <select wire:model="operatorName" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('operatorName') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">{{ __('parametres.placeholder_selectionner') }}</option>
                    <option>MTN MoMo</option>
                    <option>Moov Money</option>
                    <option>Celtiis Cash</option>
                </select>
                @error('operatorName') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_numero_telephone') }}</label>
                <input wire:model="phoneNumber" type="tel" placeholder="+229 XX XX XX XX" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('phoneNumber') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('phoneNumber') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_titulaire_ligne') }}</label>
                <input wire:model="holderName" type="text" placeholder="ex : M. Olouchègoun" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_numero_serie_sim') }}</label>
                <input wire:model="simSerial" type="text" placeholder="Optionnel" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_sous_compte') }}</label>
                <input wire:model="accountCode" type="text" placeholder="ex : 521203" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-add-momo' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('parametres.btn_annuler') }}</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ __('parametres.btn_enregistrer') }}</button>
            </div>
        </form>
    </x-modal>

    <x-modal name="modal-virement-interne" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ __('parametres.titre_virement_interne') }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-virement-interne' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>

        <p class="text-[11px] text-outline mb-md">{{ __('parametres.desc_virement_interne') }}</p>

        <form wire:submit="submitTransfer" class="space-y-md">
            <div>
                <label for="vir-source" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_compte_source') }}</label>
                <select id="vir-source" wire:model="transferFromId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('transferFromId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">{{ __('parametres.placeholder_selectionner') }}</option>
                    @foreach($this->transferableAccounts as $compte)
                        <option value="{{ $compte->id }}">{{ $compte->label }} — {{ number_format($compte->balance, 0, ',', ' ') }} FCFA</option>
                    @endforeach
                </select>
                @error('transferFromId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            <div>
                <label for="vir-dest" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_compte_dest') }}</label>
                <select id="vir-dest" wire:model="transferToId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('transferToId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">{{ __('parametres.placeholder_selectionner') }}</option>
                    @foreach($this->transferableAccounts as $compte)
                        <option value="{{ $compte->id }}">{{ $compte->label }} — {{ number_format($compte->balance, 0, ',', ' ') }} FCFA</option>
                    @endforeach
                </select>
                @error('transferToId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            <div>
                <label for="vir-montant" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_montant_virement') }}</label>
                <input id="vir-montant" type="number" min="1" step="1" wire:model="transferAmount" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('transferAmount') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('transferAmount') <p class="invalid-feedback">{{ $message }}</p> @enderror
                <p class="text-[10px] text-outline mt-xs">{{ __('parametres.aide_virement_solde') }}</p>
            </div>

            <div>
                <label for="vir-motif" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_motif_virement') }}</label>
                <input id="vir-motif" type="text" wire:model="transferReason" placeholder="Dépôt des recettes de la semaine en banque" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                @error('transferReason') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-virement-interne' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('parametres.btn_annuler') }}</button>
                <button type="submit" class="flex items-center gap-xs px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">
                    <span class="material-symbols-outlined text-[18px]">swap_horiz</span>{{ __('parametres.btn_effectuer_virement') }}
                </button>
            </div>
        </form>
    </x-modal>
</div>
