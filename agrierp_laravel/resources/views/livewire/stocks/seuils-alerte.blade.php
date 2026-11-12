<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">notification_important</span>{{ __('stocks.titre_seuils_alerte') }}
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">{{ __('stocks.desc_seuils_alerte') }}</p>
        </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md mb-lg">
        <x-kpi-card :label="__('stocks.kpi_produits_sous_seuil')" icon="warning" color="red" :value="$this->kpis['produits_sous_seuil']" />
        <x-kpi-card :label="__('stocks.kpi_seuils_configures')" icon="tune" color="emerald" :value="$this->kpis['seuils_configures']" />
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md flex flex-col md:flex-row items-stretch md:items-center justify-between gap-sm border-b border-outline-variant">
            <div class="relative flex-1 md:max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="{{ __('stocks.placeholder_rechercher') }}" class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
            </div>
            <select wire:model.live="statusFilter" class="border border-outline-variant rounded-lg text-xs px-sm py-2 bg-white w-full md:w-auto">
                <option value="">{{ __('stocks.filtre_tous_statuts') }}</option>
                <option value="Normal">{{ __('stocks.badge_normal') }}</option>
                <option value="Critique">{{ __('stocks.badge_critique') }}</option>
            </select>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_produit') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_stock_actuel') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_seuil_configure') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_statut') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->products as $i => $product)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="{{ __('stocks.col_produit') }}" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $product->name }}</td>
                            <td data-label="{{ __('stocks.col_stock_actuel') }}" class="px-md py-sm text-xs">{{ rtrim(rtrim(number_format($product->stock_qty, 2, '.', ''), '0'), '.') }}</td>
                            <td data-label="{{ __('stocks.col_seuil_configure') }}" class="px-md py-sm text-xs">{{ $product->alert_threshold ?: '—' }}</td>
                            <td data-label="{{ __('stocks.col_statut') }}" class="px-md py-sm">
                                @if($product->is_critique)
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-bg text-error-deep border-error-deep/30">{{ __('stocks.badge_critique') }}</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">{{ __('stocks.badge_normal') }}</span>
                                @endif
                            </td>
                            <td data-label="{{ __('stocks.col_actions') }}" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button" wire:click="editThreshold('{{ $product->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="5" class="px-md py-lg text-center text-outline">{{ __('stocks.msg_aucun_produit') }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-edit-seuil" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ __('stocks.modal_titre_configurer_seuil') }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-edit-seuil' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveThreshold" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('stocks.label_seuil_alerte_modal') }}</label>
                <input wire:model="threshold" type="number" min="0" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('threshold') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('threshold') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-edit-seuil' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('stocks.bouton_annuler') }}</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ __('stocks.bouton_enregistrer') }}</button>
            </div>
        </form>
    </x-modal>
</div>
