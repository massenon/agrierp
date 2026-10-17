<div
    x-data="{
        activeIndex: -1,
        flatItems() {
            return Array.from($refs.resultsPanel ? $refs.resultsPanel.querySelectorAll('[data-search-item]') : []);
        },
        moveDown() {
            const items = this.flatItems();
            if (!items.length) return;
            this.activeIndex = Math.min(this.activeIndex + 1, items.length - 1);
            items[this.activeIndex]?.scrollIntoView({ block: 'nearest' });
        },
        moveUp() {
            const items = this.flatItems();
            if (!items.length) return;
            this.activeIndex = Math.max(this.activeIndex - 1, 0);
            items[this.activeIndex]?.scrollIntoView({ block: 'nearest' });
        },
        selectActive() {
            const items = this.flatItems();
            if (this.activeIndex >= 0 && items[this.activeIndex]) {
                items[this.activeIndex].click();
            }
        }
    }"
    x-on:keydown.window.ctrl.k.prevent="$refs.searchInput.focus(); $refs.searchInput.select()"
    x-on:keydown.window.cmd.k.prevent="$refs.searchInput.focus(); $refs.searchInput.select()"
    class="relative"
>
    <div class="hidden md:flex items-center gap-xs bg-surface-zebra border border-outline-variant rounded-full px-md py-xs w-64 focus-within:ring-2 focus-within:ring-brand-emerald" x-on:click.outside="$wire.close(); activeIndex = -1">
        <span class="material-symbols-outlined text-outline text-[16px]">search</span>
        <input
            x-ref="searchInput"
            wire:model.live.debounce.150ms="query"
            type="text"
            placeholder="Recherche globale ERP… (Ctrl+K)"
            class="bg-transparent outline-none text-xs w-full placeholder:text-outline"
            x-on:keydown.down.prevent="moveDown()"
            x-on:keydown.up.prevent="moveUp()"
            x-on:keydown.enter.prevent="selectActive()"
            x-on:keydown.escape="$wire.close(); activeIndex = -1; $refs.searchInput.blur()"
        >
        @if($query)
            <button type="button" wire:click="$set('query', '')" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined text-[14px]">close</span></button>
        @endif

        @if($showResults)
            <div x-ref="resultsPanel" class="absolute top-full left-0 mt-xs w-96 max-h-[70vh] overflow-y-auto bg-white border border-outline-variant rounded-lg shadow-xl z-[200] py-xs">
                @php $globalIndex = 0; @endphp
                @forelse($this->results as $domain)
                    <div class="px-md py-xs">
                        <p class="text-[10px] font-bold uppercase text-{{ $domain['color'] === 'emerald' ? 'brand-emerald' : ($domain['color'] === 'blue' ? 'info-blue' : 'brand-maize-ink') }} flex items-center gap-xs">
                            <span class="material-symbols-outlined text-[14px]">{{ $domain['icon'] }}</span>{{ $domain['label'] }} ({{ count($domain['items']) }})
                        </p>
                        @foreach($domain['items'] as $item)
                            <a href="{{ $item['url'] }}" data-search-item
                               class="flex items-center justify-between gap-sm px-sm py-xs rounded-lg hover:bg-surface-zebra text-xs"
                               :class="activeIndex === {{ $globalIndex }} ? 'bg-surface-zebra' : ''">
                                <span class="flex items-center gap-xs min-w-0">
                                    <span class="material-symbols-outlined text-[16px] {{ !empty($item['critical']) ? 'text-error-red' : 'text-outline' }}">{{ $item['icon'] }}</span>
                                    <span class="min-w-0">
                                        <span class="block font-semibold text-on-surface truncate">{{ $item['label'] }}</span>
                                        <span class="block text-[10px] {{ !empty($item['critical']) ? 'text-error-red font-bold' : 'text-outline' }} truncate">{{ $item['sublabel'] }}</span>
                                    </span>
                                </span>
                                <span class="material-symbols-outlined text-[14px] text-outline flex-shrink-0">chevron_right</span>
                            </a>
                            @php $globalIndex++; @endphp
                        @endforeach
                    </div>
                @empty
                    <p class="px-md py-md text-xs text-outline text-center">Aucun résultat pour « {{ $query }} ».</p>
                @endforelse
            </div>
        @endif
    </div>

    <div class="md:hidden" x-data="{ mobileOpen: false }">
        <button type="button" x-on:click="mobileOpen = true" class="text-outline"><span class="material-symbols-outlined">search</span></button>
        <div x-show="mobileOpen" x-cloak class="fixed inset-0 bg-white z-[300] p-md flex flex-col">
            <div class="flex items-center gap-sm mb-md">
                <span class="material-symbols-outlined text-outline">search</span>
                <input
                    wire:model.live.debounce.150ms="query"
                    type="text"
                    placeholder="Recherche globale ERP…"
                    class="flex-1 border-0 outline-none text-sm"
                    autofocus
                    x-on:keydown.escape="mobileOpen = false; $wire.close()"
                >
                <button type="button" x-on:click="mobileOpen = false; $wire.close()" class="text-outline"><span class="material-symbols-outlined">close</span></button>
            </div>
            <div class="flex-1 overflow-y-auto">
                @if($showResults)
                    @forelse($this->results as $domain)
                        <div class="mb-md">
                            <p class="text-[10px] font-bold uppercase text-{{ $domain['color'] === 'emerald' ? 'brand-emerald' : ($domain['color'] === 'blue' ? 'info-blue' : 'brand-maize-ink') }} flex items-center gap-xs mb-xs">
                                <span class="material-symbols-outlined text-[14px]">{{ $domain['icon'] }}</span>{{ $domain['label'] }} ({{ count($domain['items']) }})
                            </p>
                            @foreach($domain['items'] as $item)
                                <a href="{{ $item['url'] }}" class="flex items-center justify-between gap-sm px-sm py-sm rounded-lg hover:bg-surface-zebra text-sm border-b border-outline-variant/50">
                                    <span class="flex items-center gap-xs min-w-0">
                                        <span class="material-symbols-outlined text-[18px] {{ !empty($item['critical']) ? 'text-error-red' : 'text-outline' }}">{{ $item['icon'] }}</span>
                                        <span class="min-w-0">
                                            <span class="block font-semibold text-on-surface truncate">{{ $item['label'] }}</span>
                                            <span class="block text-[11px] {{ !empty($item['critical']) ? 'text-error-red font-bold' : 'text-outline' }} truncate">{{ $item['sublabel'] }}</span>
                                        </span>
                                    </span>
                                    <span class="material-symbols-outlined text-[16px] text-outline flex-shrink-0">chevron_right</span>
                                </a>
                            @endforeach
                        </div>
                    @empty
                        <p class="py-md text-sm text-outline text-center">Aucun résultat pour « {{ $query }} ».</p>
                    @endforelse
                @else
                    <p class="py-md text-sm text-outline text-center">Saisissez au moins 2 caractères pour lancer la recherche.</p>
                @endif
            </div>
        </div>
    </div>
</div>
