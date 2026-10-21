@props([
    'name',
    'maxWidth' => 'sm', // sm | md | lg | xl
])
@php
    // Classes statiques (jamais de construction dynamique — voir kpi-card.blade.php)
    $widths = ['sm' => 'max-w-sm', 'md' => 'max-w-md', 'lg' => 'max-w-lg', 'xl' => 'max-w-3xl'];
    $widthClass = $widths[$maxWidth] ?? $widths['sm'];
@endphp
<div
    x-data="{ show: false }"
    x-on:open-modal.window="if ($event.detail.name === '{{ $name }}') show = true"
    x-on:close-modal.window="if (!$event.detail || $event.detail.name === '{{ $name }}') show = false"
    x-on:keydown.escape.window="show = false"
    x-show="show"
    x-cloak
    class="fixed inset-0 bg-black/50 z-[110] flex items-center justify-center p-md">
    <div @click.outside="show = false" class="bg-white rounded-lg shadow-xl w-full {{ $widthClass }} p-lg max-h-[85vh] overflow-y-auto">
        {{ $slot }}
    </div>
</div>
