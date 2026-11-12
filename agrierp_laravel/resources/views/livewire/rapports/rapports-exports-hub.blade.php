<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">bar_chart</span>{{ __('rapports.hub_titre') }}
        </h2>
        <p class="text-xs text-outline mt-xs">{{ __('rapports.hub_sous_titre') }}</p>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-lg flex flex-wrap items-center gap-sm">
        <input wire:model.live="startDate" type="date" min="{{ \App\Support\ExerciceChoisi::bornes()[0] }}" max="{{ \App\Support\ExerciceChoisi::bornes()[1] }}" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
        <span class="text-xs text-outline">{{ __('rapports.hub_date_au') }}</span>
        <input wire:model.live="endDate" type="date" min="{{ \App\Support\ExerciceChoisi::bornes()[0] }}" max="{{ \App\Support\ExerciceChoisi::bornes()[1] }}" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
        <div class="flex items-center gap-xs ml-auto">
            @can('export-rapports')
            <button type="button" wire:click="exportPdf" wire:loading.attr="disabled" wire:target="exportPdf" class="flex items-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>{{ __('rapports.hub_exporter_pdf') }}
            </button>
            <button type="button" wire:click="exportExcel" wire:loading.attr="disabled" wire:target="exportExcel" class="flex items-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">table_view</span>{{ __('rapports.hub_exporter_excel') }}
            </button>
            @endcan
        </div>
    </div>

    <div class="flex items-center gap-xs border-b border-outline-variant mb-lg overflow-x-auto">
        <button type="button" wire:click="$set('tab', 'recettes-depenses')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap flex items-center gap-xs {{ $tab === 'recettes-depenses' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}"><span class="material-symbols-outlined text-[16px]">payments</span>{{ __('rapports.hub_onglet_recettes_depenses') }}</button>
        <button type="button" wire:click="$set('tab', 'tresorerie')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap flex items-center gap-xs {{ $tab === 'tresorerie' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}"><span class="material-symbols-outlined text-[16px]">account_balance_wallet</span>{{ __('rapports.hub_onglet_tresorerie') }}</button>
        <button type="button" wire:click="$set('tab', 'creances')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap flex items-center gap-xs {{ $tab === 'creances' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}"><span class="material-symbols-outlined text-[16px]">request_quote</span>{{ __('rapports.hub_onglet_creances') }}</button>
        <button type="button" wire:click="$set('tab', 'dettes')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap flex items-center gap-xs {{ $tab === 'dettes' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}"><span class="material-symbols-outlined text-[16px]">local_shipping</span>{{ __('rapports.hub_onglet_dettes') }}</button>
        <button type="button" wire:click="$set('tab', 'elevage-synth')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap flex items-center gap-xs {{ $tab === 'elevage-synth' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}"><span class="material-symbols-outlined text-[16px]">pets</span>{{ __('rapports.hub_onglet_elevage') }}</button>
        <button type="button" wire:click="$set('tab', 'stocks-synth')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap flex items-center gap-xs {{ $tab === 'stocks-synth' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}"><span class="material-symbols-outlined text-[16px]">inventory_2</span>{{ __('rapports.hub_onglet_stocks') }}</button>
    </div>

    @if($tab === 'recettes-depenses')
        <livewire:rapports.recettes-depenses :start-date="$startDate" :end-date="$endDate" :key="'rd-'.$startDate.$endDate" />
    @endif
    @if($tab === 'tresorerie')
        <livewire:rapports.tresorerie :start-date="$startDate" :end-date="$endDate" :key="'tr-'.$startDate.$endDate" />
    @endif
    @if($tab === 'creances')
        <livewire:rapports.creances :start-date="$startDate" :end-date="$endDate" :key="'cr-'.$startDate.$endDate" />
    @endif
    @if($tab === 'dettes')
        <livewire:rapports.dettes :start-date="$startDate" :end-date="$endDate" :key="'dt-'.$startDate.$endDate" />
    @endif
    @if($tab === 'elevage-synth')
        <livewire:rapports.elevage-synth :start-date="$startDate" :end-date="$endDate" :key="'es-'.$startDate.$endDate" />
    @endif
    @if($tab === 'stocks-synth')
        <livewire:rapports.stocks-synth :start-date="$startDate" :end-date="$endDate" :key="'ss-'.$startDate.$endDate" />
    @endif
</div>
