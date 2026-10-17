@props([
    'label' => 'Ce module',
    'since' => null, // ex. "Sprint 4 (Ventes Ferme)"
])
<div {{ $attributes->class(['flex flex-col items-center justify-center text-center gap-xs py-lg px-md text-outline']) }}>
    <span class="material-symbols-outlined text-[32px] text-outline/40">hourglass_empty</span>
    <p class="text-xs font-semibold text-outline">{{ $label }} sera alimenté en données réelles dès sa mise en œuvre.</p>
    @if($since)
        <p class="text-[10px] text-outline/70">Prévu : {{ $since }}</p>
    @endif
</div>
