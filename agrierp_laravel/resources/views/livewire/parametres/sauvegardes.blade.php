<div class="mt-md space-y-lg">
    <div class="border-b border-outline-variant pb-md flex flex-col sm:flex-row sm:items-end sm:justify-between gap-sm">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">backup</span>{{ __('parametres.titre_sauvegardes') }}
            </h2>
            <p class="text-xs text-outline mt-xs">{{ __('parametres.desc_sauvegardes') }}</p>
        </div>
        <button type="button" wire:click="genererSauvegarde" wire:loading.attr="disabled" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">save</span>{{ __('parametres.btn_generer_sauvegarde_v2') }}
        </button>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-2 gap-lg">
        <div class="bg-white border border-outline-variant rounded-lg p-md">
            <h3 class="font-bold text-sm text-brand-forest mb-md flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">upload</span>{{ __('parametres.section_export_module') }}</h3>
            <div class="space-y-sm">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_choisir_module') }}</label>
                    <select wire:model="exportModule" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                        <option value="">{{ __('parametres.placeholder_selectionner') }}</option>
                        @foreach($this->modules as $module)
                            <option value="{{ $module }}">{{ $module }}</option>
                        @endforeach
                    </select>
                </div>
                <button type="button" wire:click="exporterModule" wire:loading.attr="disabled" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
                    <span class="material-symbols-outlined text-[18px]">download</span>{{ __('parametres.btn_exporter_module') }}
                </button>
                <p class="text-[10px] text-outline">{{ __('parametres.aide_export_module') }}</p>
            </div>
        </div>

        <div class="bg-white border border-outline-variant rounded-lg p-md">
            <h3 class="font-bold text-sm text-brand-forest mb-md flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">download</span>{{ __('parametres.section_import_module') }}</h3>
            <div class="bg-accent-yellow/10 border border-accent-yellow/40 rounded-lg p-sm text-[11px] text-brand-forest mb-md">{{ __('parametres.info_import_module') }}</div>
            <div class="space-y-sm">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_sauvegarde') }}</label>
                    <input wire:model="importFile" type="file" accept=".json" class="w-full text-xs">
                    <p class="text-[10px] text-outline mt-xs">{{ __('parametres.label_choisir_fichier') }}</p>
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_module_cible') }}</label>
                    <select wire:model="importTargetModule" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                        <option value="">{{ __('parametres.placeholder_selectionner') }}</option>
                        @foreach($this->modules as $module)
                            <option value="{{ $module }}">{{ $module }}</option>
                        @endforeach
                    </select>
                </div>
                <button type="button" x-on:click="$dispatch('open-modal', { name: 'modal-confirm-import' })" class="flex items-center gap-xs bg-error-deep hover:bg-red-800 text-white font-bold text-xs px-md py-sm rounded-full">
                    <span class="material-symbols-outlined text-[18px]">upload_file</span>{{ __('parametres.btn_importer') }}
                </button>
            </div>
        </div>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg overflow-hidden">
        <div class="px-md py-sm border-b border-outline-variant"><h3 class="text-sm font-bold text-brand-forest">{{ __('parametres.titre_sauvegardes') }}</h3></div>
        <div class="overflow-x-auto">
            <table class="w-full text-xs">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_fichier') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_date') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_table') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_action') }}</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->backups as $i => $backup)
                        <tr class="border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td class="px-md py-sm font-mono text-[11px]">{{ $backup['name'] }}</td>
                            <td class="px-md py-sm">{{ $backup['date'] }}</td>
                            <td class="px-md py-sm">{{ $backup['table'] ?? '—' }}</td>
                            <td class="px-md py-sm text-right">
                                <button type="button" wire:click="telecharger('{{ $backup['path'] }}')" class="flex items-center gap-xs text-brand-emerald hover:text-brand-forest text-[11px] font-bold ml-auto">
                                    <span class="material-symbols-outlined text-[16px]">download</span>{{ __('parametres.btn_telecharger') }}
                                </button>
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="4" class="px-md py-md text-center text-outline">{{ __('parametres.msg_aucune_sauvegarde_v2') }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-confirm-import" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ __('parametres.titre_import_module') }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-confirm-import' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <p class="text-sm text-outline mb-md">{{ __('parametres.desc_import_module') }}</p>
        <div class="flex justify-end gap-sm border-t border-outline-variant pt-md">
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-confirm-import' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('parametres.btn_annuler') }}</button>
            <button type="button" wire:click="importerModule" x-on:click="$dispatch('close-modal', { name: 'modal-confirm-import' })" class="px-md py-sm rounded-lg bg-error-deep text-white text-sm font-bold hover:bg-red-800">{{ __('parametres.btn_confirmer_import') }}</button>
        </div>
    </x-modal>
</div>
