@props([
    'headers' => [],
    'wireModel' => null,       // nom de la propriété Livewire du composant appelant (ex. "search")
    'searchPlaceholder' => 'Rechercher…',
])
<div {{ $attributes->class(['bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden']) }}>
    @if($wireModel)
        <div class="p-md border-b border-outline-variant">
            <div class="flex items-center gap-xs bg-surface-zebra border border-outline-variant rounded-full px-md py-xs max-w-xs">
                <span class="material-symbols-outlined text-outline text-[16px]">search</span>
                <input type="text"
                    wire:model.live.debounce.300ms="{{ $wireModel }}"
                    placeholder="{{ $searchPlaceholder }}"
                    class="bg-transparent outline-none text-xs w-full placeholder:text-outline border-0 focus:ring-0 p-0">
            </div>
        </div>
    @endif

    <div class="overflow-x-auto">
        <table class="rtable w-full text-left">
            @if(count($headers))
                <thead class="bg-surface-zebra">
                    <tr>
                        @foreach($headers as $header)
                            <th class="px-md py-sm text-[10px] font-bold uppercase text-outline">{{ $header }}</th>
                        @endforeach
                    </tr>
                </thead>
            @endif
            <tbody wire:loading.class="opacity-50">
                {{ $slot }}
            </tbody>
        </table>
    </div>
</div>
