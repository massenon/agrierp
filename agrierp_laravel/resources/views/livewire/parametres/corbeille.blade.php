<div class="mt-md space-y-md">
    <div class="border-b border-outline-variant pb-md flex flex-col sm:flex-row sm:items-end sm:justify-between gap-sm">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">delete_sweep</span>{{ __('parametres.titre_corbeille') }}
            </h2>
            <p class="text-xs text-outline mt-xs">{{ __('parametres.desc_corbeille') }}</p>
        </div>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-3 gap-md">
        <x-kpi-card :label="__('parametres.kpi_archives')" icon="inventory_2" color="emerald" :value="$this->kpis['archives']" />
        <x-kpi-card :label="__('parametres.kpi_restaurables')" icon="restore" color="blue" :value="$this->kpis['restaurables']" />
        <x-kpi-card :label="__('parametres.kpi_supprimables')" icon="delete_forever" color="maize" :value="$this->kpis['supprimables']" />
    </div>

    <div class="bg-info-blue/10 border border-info-blue/30 rounded-lg p-md text-xs text-brand-forest flex items-start gap-xs">
        <span class="material-symbols-outlined text-info-blue text-[18px] flex-shrink-0">info</span>
        <span>{{ __('parametres.info_corbeille') }}</span>
    </div>

    <form wire:submit.prevent class="bg-white border border-outline-variant rounded-lg p-md grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-sm items-end">
        <div>
            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_recherche') }}</label>
            <input wire:model.live.debounce.300ms="search" type="text" placeholder="{{ __('parametres.placeholder_recherche') }}" class="w-full h-11 px-md border border-outline-variant rounded-lg text-xs">
        </div>
        <div>
            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_type') }}</label>
            <select wire:model.live="filterType" class="w-full h-11 px-md border border-outline-variant rounded-lg text-xs bg-white">
                <option value="">{{ __('parametres.filtre_tous_types') }}</option>
                @foreach($this->types as $type)
                    <option value="{{ $type }}">{{ $type }}</option>
                @endforeach
            </select>
        </div>
        <div>
            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_archive_du') }}</label>
            <input wire:model.live="dateFrom" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-xs">
        </div>
        <div>
            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_archive_au') }}</label>
            <input wire:model.live="dateTo" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-xs">
        </div>
        <div class="sm:col-span-2 lg:col-span-4 flex justify-end">
            <button type="button" wire:click="reinitialiserFiltres" class="flex items-center gap-xs text-xs text-outline hover:text-brand-forest">
                <span class="material-symbols-outlined text-[16px]">refresh</span>{{ __('parametres.btn_reinitialiser_filtres') }}
            </button>
        </div>
    </form>

    <div class="bg-white border border-outline-variant rounded-lg overflow-x-auto">
        <table class="rtable w-full text-xs">
            <thead class="bg-surface-zebra border-b border-outline-variant">
                <tr>
                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_type') }}</th>
                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_element') }}</th>
                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_detail') }}</th>
                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_module') }}</th>
                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_archive_le') }}</th>
                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_archive_par') }}</th>
                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_actions') }}</th>
                </tr>
            </thead>
            <tbody>
                @forelse($this->items as $i => $item)
                    <tr wire:key="corbeille-{{ $item['id'] }}" class="border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                        <td data-label="Type" class="px-md py-sm">{{ $item['type'] }}</td>
                        <td data-label="Élément" class="px-md py-sm font-semibold">{{ $item['label'] }}</td>
                        <td data-label="Détail" class="px-md py-sm text-outline">{{ $item['detail'] ?? '—' }}</td>
                        <td data-label="Module" class="px-md py-sm">{{ $item['module'] ?? '—' }}</td>
                        <td data-label="Archivé le" class="px-md py-sm">{{ $item['archive_le']?->format('d/m/Y') ?? '—' }}</td>
                        <td data-label="Archivé par" class="px-md py-sm">{{ $item['archive_par'] ?? '—' }}</td>
                        <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap space-x-xs">
                            @if($item['restaurable'])
                                <button type="button" wire:click="restaurer('{{ $item['id'] }}', '{{ $item['type_code'] }}')" wire:confirm="{{ __('parametres.btn_restaurer') }} ?" class="text-brand-emerald hover:text-brand-forest" title="{{ __('parametres.btn_restaurer') }}">
                                    <span class="material-symbols-outlined text-[18px]">restore</span>
                                </button>
                            @else
                                <span class="text-[10px] text-outline italic" title="{{ $item['raison_non_restaurable'] ?? '' }}">{{ __('parametres.prefix_non_restaurable') }}</span>
                            @endif
                            @if($item['supprimable'])
                                <button type="button" x-on:click="$dispatch('open-modal', { name: 'suppr-def-{{ $item['id'] }}' })" class="text-error-deep hover:text-red-800" title="{{ __('parametres.btn_supprimer_definitif') }}">
                                    <span class="material-symbols-outlined text-[18px]">delete_forever</span>
                                </button>
                                <x-modal-confirm-hard-delete
                                    :name="'suppr-def-'.$item['id']"
                                    :item-label="$item['label']"
                                    :action="'supprimerDefinitivement(\''.$item['id'].'\', \''.$item['type_code'].'\')'"/>
                            @else
                                <span class="text-[10px] text-outline italic" title="{{ $item['raison_non_supprimable'] ?? '' }}">{{ __('parametres.prefix_suppression_impossible') }}</span>
                            @endif
                        </td>
                    </tr>
                @empty
                    <tr>
                        <td colspan="7" class="px-md py-lg text-center text-outline">
                            @if($search || $filterType || $dateFrom || $dateTo)
                                {{ __('parametres.msg_aucun_element_recherche') }}
                            @else
                                {{ __('parametres.msg_corbeille_vide') }}
                            @endif
                        </td>
                    </tr>
                @endforelse
            </tbody>
        </table>
    </div>
</div>
