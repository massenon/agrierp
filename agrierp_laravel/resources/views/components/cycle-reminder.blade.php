@props([
    'steps', // array de ['label' => string, 'active' => bool]
])
<div {{ $attributes->class(['bg-info-blue/5 border border-info-blue/20 rounded-lg p-md flex items-center gap-md flex-wrap']) }}>
    <span class="material-symbols-outlined text-info-blue text-[20px] flex-shrink-0">event_repeat</span>
    <p class="text-xs font-bold text-brand-forest flex-shrink-0">Rappel du cycle :</p>
    <div class="flex items-center gap-xs flex-wrap text-[11px] font-bold">
        @foreach($steps as $i => $step)
            @if($i > 0)
                <span class="material-symbols-outlined text-outline text-[14px]">arrow_forward</span>
            @endif
            @if(!empty($step['active']))
                <span class="px-sm py-1 rounded-full bg-brand-emerald/10 border border-brand-emerald/30 text-brand-emerald">{{ $step['label'] }}</span>
            @else
                <span class="px-sm py-1 rounded-full bg-white border border-outline-variant text-brand-forest">{{ $step['label'] }}</span>
            @endif
        @endforeach
    </div>
</div>
