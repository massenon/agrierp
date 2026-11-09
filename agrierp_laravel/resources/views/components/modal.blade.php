@props([
    'name',
    'maxWidth' => 'sm', // sm | md | lg | xl | 2xl
    // true : la modale est déplacée sous <body>. À employer quand elle est rendue dans un
    // conteneur qui crée son propre empilement (l'en-tête collant z-30 passe sous la barre
    // latérale z-50 : la modale était alors rognée à gauche par la barre).
    'teleport' => false,
])
@php
    // Classes statiques (jamais de construction dynamique — voir kpi-card.blade.php)
    $widths = ['sm' => 'max-w-sm', 'md' => 'max-w-md', 'lg' => 'max-w-lg', 'xl' => 'max-w-3xl', '2xl' => 'max-w-5xl'];
    $widthClass = $widths[$maxWidth] ?? $widths['sm'];
@endphp
@if($teleport)
<div x-data><template x-teleport="body">
@endif
<div
    x-data="{ show: false }"
    x-on:open-modal.window="if ($event.detail.name === '{{ $name }}') show = true"
    x-on:close-modal.window="if (!$event.detail || $event.detail.name === '{{ $name }}') show = false"
    x-on:keydown.escape.window="show = false"
    x-show="show"
    x-cloak
    class="fixed inset-0 bg-black/50 z-[110] flex items-center justify-center p-md">
    <div @click.outside="show = false" class="modal-panel bg-white rounded-lg shadow-xl w-full {{ $widthClass }} p-md sm:p-lg max-h-[85vh] max-h-[85dvh] overflow-y-auto">
        {{ $slot }}
    </div>
</div>
@if($teleport)
</template></div>
@endif
