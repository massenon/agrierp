@props([
    'tabs',                  // array de ['key' => string, 'label' => string, 'icon' => string]
    'active',                // clé de l'onglet actif (valeur de la propriété Livewire #[Url])
    'wireProperty' => 'tab', // nom de la propriété Livewire liée (Document 06 §4 : #[Url] public string $tab = 'default';)
])
<div {{ $attributes }}>
    <div class="flex items-center gap-xs border-b border-outline-variant bg-white px-md py-xs flex-wrap flex-shrink-0">
        @foreach($tabs as $t)
            <button
                type="button"
                wire:click="$set('{{ $wireProperty }}', '{{ $t['key'] }}')"
                @class([
                    'px-md py-2 text-xs font-bold border-b-2 whitespace-nowrap flex items-center gap-1 rounded-t-lg',
                    'border-brand-emerald text-brand-emerald' => $active === $t['key'],
                    'border-transparent text-outline' => $active !== $t['key'],
                ])>
                <span class="material-symbols-outlined text-[18px]">{{ $t['icon'] }}</span>{{ $t['label'] }}
            </button>
        @endforeach
    </div>

    <div class="mt-md">
        {{ $slot }}
    </div>
</div>
