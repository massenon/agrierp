<div class="mt-md">
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">account_balance_wallet</span>Modes de Paiement
            </h2>
            <p class="text-xs text-outline mt-xs">Comptes de trésorerie (Classe 5 SYSCOHADA) : caisse, banques et mobile money.</p>
        </div>
        @can('manage-comptabilite')
            <button type="button" wire:click="openTransfer" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all">
                <span class="material-symbols-outlined text-[18px]">swap_horiz</span>Virement Interne
            </button>
        @endcan
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-3 gap-md mb-lg">
        <x-kpi-card label="Solde Caisse (531)" icon="payments" color="emerald" :value="number_format($this->kpis['caisse'], 0, ',', ' ').' F'" />
        <x-kpi-card label="Solde Banques (521)" icon="account_balance" color="blue" :value="number_format($this->kpis['banques'], 0, ',', ' ').' F'" />
        <x-kpi-card label="Solde Mobile Money (5212)" icon="smartphone" color="maize" :value="number_format($this->kpis['mobile_money'], 0, ',', ' ').' F'" />
    </div>

    <div class="mb-lg">
        <div class="flex items-center justify-between mb-sm">
            <h3 class="text-sm font-bold text-brand-forest flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">payments</span>Caisse Physique (531)</h3>
        </div>
        @foreach($this->caisseAccounts as $account)
            <div class="bg-white border border-outline-variant rounded-lg p-md flex items-center justify-between">
                <div>
                    <p class="text-sm font-bold text-brand-forest">{{ $account->label }}</p>
                    <p class="text-xs text-outline">Compte {{ $account->account_code }}</p>
                </div>
                <div class="text-right">
                    <p class="text-lg font-extrabold text-brand-emerald">{{ number_format($account->balance, 0, ',', ' ') }} FCFA</p>
                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[10px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Actif</span>
                </div>
            </div>
        @endforeach
    </div>

    <div class="mb-lg">
        <div class="flex items-center justify-between mb-sm">
            <h3 class="text-sm font-bold text-brand-forest flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">account_balance</span>Comptes Bancaires - Multi-Banques (521)</h3>
            <button type="button" wire:click="openAddBank" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-[11px] px-md py-2 rounded-full"><span class="material-symbols-outlined text-[16px]">add_circle</span>Ajouter un Compte Bancaire</button>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-md">
            @forelse($this->bankAccounts as $account)
                <div class="bg-white border border-outline-variant rounded-lg p-md">
                    <div class="flex items-center justify-between mb-sm">
                        <p class="text-sm font-bold text-brand-forest">{{ $account->label }}</p>
                        <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[10px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Actif</span>
                    </div>
                    <p class="text-xs text-outline">Titulaire : {{ $account->holder_name ?? '—' }}</p>
                    <p class="text-xs text-outline">RIB : {{ $account->rib }} - IBAN : {{ $account->iban }}</p>
                    <p class="text-lg font-extrabold text-brand-emerald mt-sm">{{ number_format($account->balance, 0, ',', ' ') }} FCFA</p>
                </div>
            @empty
                <p class="text-xs text-outline md:col-span-2">Aucun compte bancaire pour le moment.</p>
            @endforelse
        </div>
    </div>

    <div>
        <div class="flex items-center justify-between mb-sm">
            <h3 class="text-sm font-bold text-brand-forest flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">smartphone</span>Mobile Money - Multi-Opérateurs (5212)</h3>
            <button type="button" wire:click="openAddMomo" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-[11px] px-md py-2 rounded-full"><span class="material-symbols-outlined text-[16px]">add_circle</span>Ajouter une Ligne Mobile Money</button>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-md">
            @forelse($this->momoAccounts as $account)
                <div class="bg-white border border-outline-variant rounded-lg p-md">
                    <div class="flex items-center justify-between mb-sm">
                        <p class="text-sm font-bold text-brand-forest">{{ $account->label }}</p>
                        <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[10px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Actif</span>
                    </div>
                    <p class="text-xs text-outline">Numéro : {{ $account->phone_number }} - Titulaire : {{ $account->holder_name ?? '—' }}</p>
                    <p class="text-lg font-extrabold text-brand-emerald mt-sm">{{ number_format($account->balance, 0, ',', ' ') }} FCFA</p>
                </div>
            @empty
                <p class="text-xs text-outline md:col-span-2">Aucune ligne Mobile Money pour le moment.</p>
            @endforelse
        </div>
    </div>

    <x-modal name="modal-add-bank" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Ajouter un Compte Bancaire</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-add-bank' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveBank" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Banque *</label>
                <select wire:model="bankName" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('bankName') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    <option>BOA Bénin</option>
                    <option>Ecobank Bénin</option>
                    <option>UBA Bénin</option>
                    <option>NSIA Banque</option>
                </select>
                @error('bankName') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Titulaire du Compte</label>
                <input wire:model="holderName" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">RIB *</label>
                <input wire:model="rib" type="text" placeholder="BJ066 01001 ..." class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('rib') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('rib') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">IBAN *</label>
                <input wire:model="iban" type="text" placeholder="BJ66BJ..." class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('iban') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('iban') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Sous-compte Auxiliaire</label>
                <input wire:model="accountCode" type="text" placeholder="ex : 521103" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-add-bank' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>

    <x-modal name="modal-add-momo" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Ajouter une Ligne Mobile Money</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-add-momo' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveMomo" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Opérateur *</label>
                <select wire:model="operatorName" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('operatorName') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    <option>MTN MoMo</option>
                    <option>Moov Money</option>
                    <option>Celtiis Cash</option>
                </select>
                @error('operatorName') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Numéro de Téléphone *</label>
                <input wire:model="phoneNumber" type="tel" placeholder="+229 XX XX XX XX" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('phoneNumber') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('phoneNumber') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Titulaire de la Ligne</label>
                <input wire:model="holderName" type="text" placeholder="ex : M. Olouchègoun" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Numéro de Série SIM</label>
                <input wire:model="simSerial" type="text" placeholder="Optionnel" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Sous-compte Auxiliaire</label>
                <input wire:model="accountCode" type="text" placeholder="ex : 521203" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-add-momo' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>

    <x-modal name="modal-virement-interne" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Virement Interne</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-virement-interne' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>

        <p class="text-[11px] text-outline mb-md">
            Déplace des fonds entre deux comptes de trésorerie. L'opération n'est ni un produit ni une charge :
            elle débite le compte destinataire et crédite le compte source au grand livre, sans toucher au résultat.
        </p>

        <form wire:submit="submitTransfer" class="space-y-md">
            <div>
                <label for="vir-source" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Compte source *</label>
                <select id="vir-source" wire:model="transferFromId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('transferFromId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->transferableAccounts as $compte)
                        <option value="{{ $compte->id }}">{{ $compte->label }} — {{ number_format($compte->balance, 0, ',', ' ') }} FCFA</option>
                    @endforeach
                </select>
                @error('transferFromId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            <div>
                <label for="vir-dest" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Compte destinataire *</label>
                <select id="vir-dest" wire:model="transferToId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('transferToId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->transferableAccounts as $compte)
                        <option value="{{ $compte->id }}">{{ $compte->label }} — {{ number_format($compte->balance, 0, ',', ' ') }} FCFA</option>
                    @endforeach
                </select>
                @error('transferToId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            <div>
                <label for="vir-montant" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Montant (FCFA) *</label>
                <input id="vir-montant" type="number" min="1" step="1" wire:model="transferAmount" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('transferAmount') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('transferAmount') <p class="invalid-feedback">{{ $message }}</p> @enderror
                <p class="text-[10px] text-outline mt-xs">Un virement supérieur au solde du compte source est refusé : on ne vire pas un argent dont on ne dispose pas.</p>
            </div>

            <div>
                <label for="vir-motif" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Motif</label>
                <input id="vir-motif" type="text" wire:model="transferReason" placeholder="Dépôt des recettes de la semaine en banque" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                @error('transferReason') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-virement-interne' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="flex items-center gap-xs px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">
                    <span class="material-symbols-outlined text-[18px]">swap_horiz</span>Effectuer le Virement
                </button>
            </div>
        </form>
    </x-modal>
</div>
