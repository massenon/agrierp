@props(['title' => 'Indicateurs Clés (KPI)'])
<div x-data="{ open: false }" {{ $attributes->class(['mb-md']) }}>
    <button @click="open = !open" class="md:hidden w-full flex items-center justify-between bg-white border border-outline-variant rounded-lg px-md py-sm shadow-sm">
        <span class="text-xs font-bold text-brand-forest flex items-center gap-xs">
            <span class="material-symbols-outlined text-[18px]">bar_chart</span>{{ $title }} (Replier / Déplier)
        </span>
        <span class="material-symbols-outlined text-[18px] kpi-chev" :class="{ 'rot': open }">expand_more</span>
    </button>

    <div class="grid grid-cols-2 xl:grid-cols-4 gap-md kpi-mobile-collapsed md:mt-0 mt-sm" :class="{ 'open': open }">
        {{ $slot }}
    </div>
</div>
