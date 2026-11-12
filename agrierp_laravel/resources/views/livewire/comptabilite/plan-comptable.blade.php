<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">menu_book</span>{{ __('comptabilite.plan_titre') }}
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">{{ __('comptabilite.plan_sous_titre') }}</p>
        </div>
        <div class="flex items-center gap-xs">
            <button type="button" wire:click="exportPlanComptablePdf" wire:loading.attr="disabled" wire:target="exportPlanComptablePdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>{{ __('comptabilite.plan_exporter_pdf') }}
            </button>
            @can('manage-comptabilite')
            <button type="button" wire:click="newAccount" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
                <span class="material-symbols-outlined text-[18px]">add_circle</span>{{ __('comptabilite.plan_nouveau_compte') }}
            </button>
            @endcan
        </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md mb-lg">
        <x-kpi-card :label="__('comptabilite.plan_kpi_comptes_actifs')" icon="menu_book" color="emerald" :value="$this->kpis['comptes_actifs']" />
        <x-kpi-card :label="__('comptabilite.plan_kpi_exercice')" icon="event" color="blue" :value="$this->kpis['exercice']" />
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md border-b border-outline-variant">
            <div class="relative max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
            </div>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('comptabilite.plan_col_numero') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('comptabilite.plan_col_intitule') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('comptabilite.plan_col_classe') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('comptabilite.plan_col_actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->accounts as $i => $account)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="N° Compte" class="px-md py-sm text-xs font-mono font-bold text-brand-emerald">{{ $account->code }}</td>
                            <td data-label="Intitulé" class="px-md py-sm text-xs font-semibold">{{ $account->label }}</td>
                            <td data-label="Classe" class="px-md py-sm text-xs">{{ $this->classLabel($account->class) }}</td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                @can('manage-comptabilite')
                                <button type="button" wire:click="editAccount('{{ $account->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                <button type="button" wire:click="archiveAccount('{{ $account->id }}')" class="text-error-deep hover:text-red-800 p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">archive</span></button>
                                @else
                                <span class="text-outline text-[10px] italic">{{ __('comptabilite.lecture_seule') }}</span>
                                @endcan
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="4" class="px-md py-lg text-center text-outline">{{ __('comptabilite.plan_vide') }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        @if($this->totalCorrespondant > $this->accounts->count())
            <div class="p-md border-t border-outline-variant flex items-center justify-between gap-sm">
                <p class="text-xs text-outline">{{ $this->accounts->count() }} {{ __('comptabilite.plan_pagination_affiches') }} {{ $this->totalCorrespondant }} — {{ __('comptabilite.plan_pagination_note') }}</p>
                <button type="button" wire:click="afficherPlus" class="px-md py-sm rounded-lg border border-outline-variant text-xs font-bold text-brand-forest hover:bg-surface-zebra">{{ __('comptabilite.plan_afficher_plus') }}</button>
            </div>
        @endif
    </div>

    <x-modal name="modal-create-plan-comptable" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingId ? __('comptabilite.plan_modal_modifier') : __('comptabilite.plan_nouveau_compte') }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-plan-comptable' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveAccount" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('comptabilite.plan_form_numero') }}</label>
                <input wire:model="code" type="text" placeholder="ex : 411" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('code') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('code') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('comptabilite.plan_form_intitule') }}</label>
                <input wire:model="label" type="text" placeholder="ex : Clients" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('label') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('label') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('comptabilite.plan_form_classe') }}</label>
                <select wire:model="class" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('class') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">{{ __('comptabilite.selectionner') }}</option>
                    <option value="1">{{ __('comptabilite.plan_classe_1') }}</option>
                    <option value="2">{{ __('comptabilite.plan_classe_2') }}</option>
                    <option value="3">{{ __('comptabilite.plan_classe_3') }}</option>
                    <option value="4">{{ __('comptabilite.plan_classe_4') }}</option>
                    <option value="5">{{ __('comptabilite.plan_classe_5') }}</option>
                    <option value="6">{{ __('comptabilite.plan_classe_6') }}</option>
                    <option value="7">{{ __('comptabilite.plan_classe_7') }}</option>
                    <option value="8">{{ __('comptabilite.plan_classe_8') }}</option>
                    <option value="9">{{ __('comptabilite.plan_classe_9') }}</option>
                </select>
                @error('class') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="flex justify-end gap-sm pt-md border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-plan-comptable' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('comptabilite.annuler') }}</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ __('comptabilite.enregistrer') }}</button>
            </div>
        </form>
    </x-modal>
</div>
