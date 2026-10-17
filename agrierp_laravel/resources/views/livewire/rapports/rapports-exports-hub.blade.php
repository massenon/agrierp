<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">bar_chart</span>Rapports &amp; Exports
        </h2>
        <p class="text-xs text-outline mt-xs">États financiers et opérationnels de la Ferme École OLOUWACHEGOUN.</p>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-lg flex flex-wrap items-center gap-sm">
        <input wire:model.live="startDate" type="date" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
        <span class="text-xs text-outline">au</span>
        <input wire:model.live="endDate" type="date" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
        <div class="flex items-center gap-xs ml-auto">
            @can('export-rapports')
            <button type="button" wire:click="exportPdf" wire:loading.attr="disabled" wire:target="exportPdf" class="flex items-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
            </button>
            <button type="button" wire:click="exportExcel" wire:loading.attr="disabled" wire:target="exportExcel" class="flex items-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">table_view</span>Exporter Excel
            </button>
            @endcan
        </div>
    </div>

    <div class="flex items-center gap-xs border-b border-outline-variant mb-lg overflow-x-auto">
        <button type="button" wire:click="$set('tab', 'recettes-depenses')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap flex items-center gap-xs {{ $tab === 'recettes-depenses' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}"><span class="material-symbols-outlined text-[16px]">payments</span>Recettes et Dépenses</button>
        <button type="button" wire:click="$set('tab', 'tresorerie')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap flex items-center gap-xs {{ $tab === 'tresorerie' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}"><span class="material-symbols-outlined text-[16px]">account_balance_wallet</span>État de Trésorerie</button>
        <button type="button" wire:click="$set('tab', 'creances')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap flex items-center gap-xs {{ $tab === 'creances' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}"><span class="material-symbols-outlined text-[16px]">request_quote</span>Créances Clients</button>
        <button type="button" wire:click="$set('tab', 'dettes')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap flex items-center gap-xs {{ $tab === 'dettes' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}"><span class="material-symbols-outlined text-[16px]">local_shipping</span>Dettes Fournisseurs</button>
        <button type="button" wire:click="$set('tab', 'elevage-synth')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap flex items-center gap-xs {{ $tab === 'elevage-synth' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}"><span class="material-symbols-outlined text-[16px]">pets</span>Rapport Élevage</button>
        <button type="button" wire:click="$set('tab', 'stocks-synth')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap flex items-center gap-xs {{ $tab === 'stocks-synth' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}"><span class="material-symbols-outlined text-[16px]">inventory_2</span>Rapport de Stocks</button>
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
