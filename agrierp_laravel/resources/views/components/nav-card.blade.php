@props([
    'href',
    'icon',
    'title',
    'description' => null,
])
<a wire:navigate href="{{ $href }}" {{ $attributes->class(['group bg-white rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md hover:border-brand-emerald hover:shadow-md transition-all']) }}>
    <div class="w-12 h-12 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0">
        <span class="material-symbols-outlined text-brand-emerald text-[24px]">{{ $icon }}</span>
    </div>
    <div class="min-w-0 flex-1">
        <p class="text-sm font-bold text-brand-forest">{{ $title }}</p>
        @if($description)
            <p class="text-[11px] text-outline">{{ $description }}</p>
        @endif
    </div>
    <span class="material-symbols-outlined text-outline group-hover:text-brand-emerald group-hover:translate-x-1 transition-all flex-shrink-0">chevron_right</span>
</a>
