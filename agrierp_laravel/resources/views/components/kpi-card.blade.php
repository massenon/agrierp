@props([
    'label',
    'icon' => null,
    'value' => null,
    'unit' => null,
    'caption' => null,
    'color' => 'emerald',   // emerald | maize | red | blue | forest
    'pending' => false,     // true tant que la table source du module n'existe pas encore
    'pendingSince' => null, // ex. "Sprint 4" — affiché dans la légende à la place de $caption
])
@php
    // Classes Tailwind COMPLÈTES et statiques pour chaque variante — jamais de
    // construction dynamique type "border-l-{$color}" (le scanner JIT de
    // Tailwind ne détecte que des chaînes littérales présentes telles
    // quelles dans le code source, cf. tailwind.config.js `content`).
    $variants = [
        'emerald' => ['border' => 'border-l-brand-emerald', 'icon' => 'text-brand-emerald'],
        'maize'   => ['border' => 'border-l-accent-yellow',  'icon' => 'text-brand-forest'],
        'red'     => ['border' => 'border-l-error-red',      'icon' => 'text-error-red'],
        'blue'    => ['border' => 'border-l-info-blue',      'icon' => 'text-info-blue'],
        'forest'  => ['border' => 'border-l-brand-forest',   'icon' => 'text-brand-forest'],
    ];
    $variant = $variants[$color] ?? $variants['emerald'];
@endphp
<div {{ $attributes->class(['kpi-card bg-white rounded-lg border border-outline-variant shadow-sm', $variant['border']]) }}>
    <div class="flex justify-between items-start">
        <span class="text-[10px] text-outline font-bold uppercase">{{ $label }}</span>
        @if($icon)
            <span class="material-symbols-outlined text-[18px] {{ $variant['icon'] }}">{{ $icon }}</span>
        @endif
    </div>

    @if($pending)
        <span class="text-lg md:text-2xl font-extrabold text-outline/50 block mt-xs">—</span>
        <p class="text-[10px] text-outline mt-xs flex items-center gap-1">
            <span class="material-symbols-outlined text-[12px]">hourglass_empty</span>
            Disponible après {{ $pendingSince ?? 'un prochain sprint' }}
        </p>
    @else
        <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs truncate">
            {{ $value }}
            @if($unit)<small class="text-xs font-normal">{{ $unit }}</small>@endif
        </span>
        @if($caption)
            <p class="text-[10px] text-outline mt-xs">{{ $caption }}</p>
        @endif
    @endif
</div>
