<div class="mt-md space-y-lg">
    <div class="border-b border-outline-variant pb-md flex flex-col sm:flex-row sm:items-end sm:justify-between gap-sm">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">percent</span>{{ __('parametres.titre_bareme_its') }}
            </h2>
            <p class="text-xs text-outline mt-xs">{{ __('parametres.desc_bareme_its') }}</p>
        </div>
    </div>

    @if(!$this->baremeConfigure)
        <div class="bg-info-blue/10 border border-info-blue/30 rounded-lg p-md text-sm flex items-start gap-sm">
            <span class="material-symbols-outlined text-info-blue text-[20px] flex-shrink-0">info</span>
            <div>
                <p class="font-bold text-brand-forest">{{ __('parametres.info_premiere_config') }}</p>
                <p class="text-xs text-outline mt-xs">{{ __('parametres.detail_premiere_config') }}</p>
            </div>
        </div>
    @elseif($this->baremeVerrouille)
        <div class="bg-accent-yellow/10 border border-accent-yellow/40 rounded-lg p-md text-sm flex items-start gap-sm">
            <span class="material-symbols-outlined text-brand-forest text-[20px] flex-shrink-0">lock</span>
            <div>
                <p class="font-bold text-brand-forest">{{ $this->bannierreVerrouillage }}</p>
            </div>
        </div>
    @endif

    <div class="bg-white border border-outline-variant rounded-lg overflow-hidden">
        <div class="flex items-center justify-between px-md py-sm border-b border-outline-variant">
            <h3 class="font-bold text-sm text-brand-forest">{{ __('parametres.titre_tranches') }}</h3>
            @unless($this->baremeVerrouille)
                <button type="button" wire:click="ajouterTranche" class="flex items-center gap-xs text-brand-emerald hover:text-brand-forest text-xs font-bold">
                    <span class="material-symbols-outlined text-[18px]">add_circle</span>{{ __('parametres.btn_ajouter_tranche') }}
                </button>
            @endunless
        </div>
        <div class="overflow-x-auto">
            <table class="w-full text-xs">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_de') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_a') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_taux') }}</th>
                        @unless($this->baremeVerrouille)
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('parametres.col_actions') }}</th>
                        @endunless
                    </tr>
                </thead>
                <tbody>
                    @forelse($tranches as $i => $tranche)
                        <tr class="border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td class="px-md py-sm">
                                @unless($this->baremeVerrouille)
                                    <input wire:model="tranches.{{ $i }}.de" type="number" min="0" class="w-28 h-8 px-sm border border-outline-variant rounded text-xs" readonly>
                                @else
                                    {{ number_format($tranche['de'], 0, ',', ' ') }} FCFA
                                @endunless
                            </td>
                            <td class="px-md py-sm">
                                @unless($this->baremeVerrouille)
                                    <input wire:model="tranches.{{ $i }}.a" type="number" min="0" placeholder="{{ __('parametres.placeholder_sans_plafond') }}" class="w-28 h-8 px-sm border border-outline-variant rounded text-xs">
                                @else
                                    {{ $tranche['a'] ? number_format($tranche['a'], 0, ',', ' ').' FCFA' : '— ' }}
                                @endunless
                            </td>
                            <td class="px-md py-sm">
                                @unless($this->baremeVerrouille)
                                    <div class="flex items-center gap-xs">
                                        <input wire:model="tranches.{{ $i }}.taux" type="number" min="0" max="100" step="0.1" class="w-20 h-8 px-sm border border-outline-variant rounded text-xs">
                                        <span>%</span>
                                    </div>
                                @else
                                    {{ $tranche['taux'] }} %
                                @endunless
                            </td>
                            @unless($this->baremeVerrouille)
                                <td class="px-md py-sm text-right">
                                    <button type="button" wire:click="retirerTranche({{ $i }})" title="{{ __('parametres.title_retirer_tranche') }}" class="text-error-deep hover:text-red-800">
                                        <span class="material-symbols-outlined text-[18px]">remove_circle</span>
                                    </button>
                                </td>
                            @endunless
                        </tr>
                    @empty
                        <tr><td colspan="4" class="px-md py-md text-center text-outline">{{ __('parametres.sim_bareme_vide') }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        @unless($this->baremeVerrouille)
            <div class="px-md py-sm border-t border-outline-variant">
                <p class="text-[10px] text-outline">{{ __('parametres.aide_tranches') }}</p>
            </div>
        @endunless
    </div>

    @unless($this->baremeVerrouille)
        <div class="flex justify-end">
            <button type="button" wire:click="enregistrerBareme" wire:loading.attr="disabled" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm px-lg py-sm rounded-full shadow-sm disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">save</span>{{ __('parametres.btn_enregistrer_bareme') }}
            </button>
        </div>
    @endunless

    <div class="bg-white border border-outline-variant rounded-lg p-md">
        <h3 class="font-bold text-sm text-brand-forest mb-md flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">calculate</span>{{ __('parametres.titre_simulation') }}</h3>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-md items-end">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('parametres.label_brut_simule') }}</label>
                <input wire:model.live.debounce.300ms="brut" type="number" min="0" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            @if($this->simulation)
                <div class="space-y-xs text-xs">
                    <div class="flex justify-between border-b border-outline-variant pb-xs"><span class="text-outline">{{ __('parametres.sim_salaire_du') }}</span><span class="font-bold">{{ number_format($this->simulation['brut'], 0, ',', ' ') }} FCFA</span></div>
                    <div class="flex justify-between border-b border-outline-variant pb-xs"><span class="text-outline">{{ __('parametres.sim_cnss_salariale') }}</span><span class="font-bold text-error-deep">− {{ number_format($this->simulation['cnss'], 0, ',', ' ') }} FCFA</span></div>
                    <div class="flex justify-between border-b border-outline-variant pb-xs"><span class="text-outline">{{ __('parametres.sim_net_imposable') }}</span><span class="font-bold">{{ number_format($this->simulation['net_imposable'], 0, ',', ' ') }} FCFA</span></div>
                    <div class="flex justify-between border-b border-outline-variant pb-xs"><span class="text-outline">{{ __('parametres.sim_its') }}</span><span class="font-bold text-error-deep">− {{ number_format($this->simulation['its'], 0, ',', ' ') }} FCFA</span></div>
                    <div class="flex justify-between border-b border-outline-variant pb-xs pt-xs"><span class="font-bold text-brand-forest">{{ __('parametres.sim_net_a_payer') }}</span><span class="font-extrabold text-brand-emerald text-sm">{{ number_format($this->simulation['net'], 0, ',', ' ') }} FCFA</span></div>
                    <div class="flex justify-between pb-xs"><span class="text-outline">{{ __('parametres.sim_charges_patronales') }}</span><span class="font-bold">{{ number_format($this->simulation['patronal'], 0, ',', ' ') }} FCFA</span></div>
                </div>
            @endif
        </div>
    </div>
</div>
