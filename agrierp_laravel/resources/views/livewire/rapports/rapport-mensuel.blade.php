<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">summarize</span>{{ __('rapports.mensuel_titre') }}
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">{{ __('rapports.mensuel_sous_titre') }}</p>
        </div>
        <div class="flex items-center gap-xs">
            <select wire:model.live="periode" class="text-sm font-bold border border-outline-variant rounded-lg px-md py-2 bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
                @foreach($this->periodes as $value => $label)
                    <option value="{{ $value }}">{{ $label }}</option>
                @endforeach
            </select>
            <button type="button" wire:click="exportRapportMensuelPdf" wire:loading.attr="disabled" wire:target="exportRapportMensuelPdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>{{ __('rapports.mensuel_exporter_pdf') }}
            </button>
        </div>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md flex flex-col md:flex-row items-stretch md:items-center justify-between gap-sm border-b border-outline-variant">
            <div class="relative flex-1 md:max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="{{ __('rapports.mensuel_rechercher_placeholder') }}" class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
            </div>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase tracking-wider">{{ __('rapports.mensuel_col_indicateur') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase tracking-wider">{{ $this->moisCourantLabel }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase tracking-wider">{{ $this->moisPrecedentLabel }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase tracking-wider">{{ __('rapports.mensuel_col_variation') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase tracking-wider">{{ __('rapports.mensuel_col_actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->indicateurs as $i => $ligne)
                        @php
                            $delta = round($ligne['courant'] - $ligne['precedent'], 2);
                            $favorable = $ligne['sens'] === 'neutre'
                                ? null
                                : ($ligne['sens'] === 'hausse_bonne' ? $delta >= 0 : $delta <= 0);
                            $decimales = $ligne['unite'] === '%' ? 1 : 0;
                        @endphp
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 transition-colors {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                            <td data-label="Indicateur" class="px-md py-sm text-xs text-on-surface whitespace-nowrap font-semibold">{{ $ligne['label'] }}</td>
                            <td data-label="Mois courant" class="px-md py-sm text-xs whitespace-nowrap font-bold">{{ number_format($ligne['courant'], $decimales, ',', ' ') }} {{ $ligne['unite'] }}</td>
                            <td data-label="Mois précédent" class="px-md py-sm text-xs text-outline whitespace-nowrap">{{ number_format($ligne['precedent'], $decimales, ',', ' ') }} {{ $ligne['unite'] }}</td>
                            <td data-label="Variation" class="px-md py-sm text-xs text-right whitespace-nowrap font-bold {{ $favorable === null ? 'text-outline' : ($favorable ? 'text-brand-emerald' : 'text-error-deep') }}">
                                {{ $delta > 0 ? '+' : '' }}{{ number_format($delta, $decimales, ',', ' ') }}
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <span class="text-outline text-[10px] italic" title="{{ __('rapports.mensuel_lecture_seule_title') }}">{{ __('rapports.mensuel_lecture_seule') }}</span>
                            </td>
                        </tr>
                    @empty
                        <tr>
                            <td colspan="5" class="px-md py-xl text-center">
                                <span class="material-symbols-outlined text-outline-variant text-[44px]">inbox</span>
                                <p class="text-sm font-semibold text-on-surface mt-sm">{{ __('rapports.mensuel_vide_titre') }}</p>
                                <p class="text-xs text-outline">{{ __('rapports.mensuel_vide_texte') }}</p>
                            </td>
                        </tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <div class="p-md border-t border-outline-variant">
            <p class="text-xs text-outline">{{ trans('rapports.mensuel_compteur', ['count' => count($this->indicateurs)]) }}</p>
        </div>
    </div>
</div>
