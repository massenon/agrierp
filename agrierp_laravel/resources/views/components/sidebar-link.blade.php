@props(['href', 'icon', 'label'])
@php $isActive = request()->is(ltrim($href, '/')); @endphp
<a wire:navigate href="{{ $href }}"
    {{ $attributes->class([
        'flex items-center gap-sm px-sm py-xs rounded-lg transition-colors',
        'bg-white/10 font-bold text-accent-yellow' => $isActive,
        'text-white/90 hover:bg-white/10' => ! $isActive,
    ]) }}>
    <span class="material-symbols-outlined text-[20px]">{{ $icon }}</span>
    <span class="text-[13px]">{{ $label }}</span>
</a>
