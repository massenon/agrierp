@php
    // Classes complètes et statiques par type — voir note dynamique dans kpi-card.blade.php
    $toastVariants = [
        'success' => ['classes' => 'bg-brand-emerald border-brand-emerald text-white', 'icon' => 'check_circle'],
        'error'   => ['classes' => 'bg-error-red border-error-red text-white', 'icon' => 'error'],
        'warning' => ['classes' => 'bg-accent-yellow border-accent-yellow text-brand-forest', 'icon' => 'warning'],
    ];
@endphp
<div
    x-data="{
        toasts: [],
        nextId: 1,
        push(message, type) {
            const id = this.nextId++;
            this.toasts.push({ id, message, type: type || 'success' });
            setTimeout(() => { this.remove(id); }, 3500);
        },
        remove(id) {
            this.toasts = this.toasts.filter(t => t.id !== id);
        },
    }"
    x-on:toast.window="push($event.detail.message, $event.detail.type)"
    id="toast-container"
    class="fixed top-4 right-4 z-[200] flex flex-col gap-sm pointer-events-none">
    <template x-for="toast in toasts" :key="toast.id">
        <div class="toast-in flex items-center gap-sm px-md py-sm rounded-lg shadow-lg border min-w-[260px] pointer-events-auto"
            :class="{
                @foreach($toastVariants as $type => $variant)
                    '{{ $variant['classes'] }}': toast.type === '{{ $type }}',
                @endforeach
            }">
            <span class="material-symbols-outlined text-[20px]"
                x-text="{
                    @foreach($toastVariants as $type => $variant)
                        {{ $type }}: '{{ $variant['icon'] }}',
                    @endforeach
                }[toast.type] || '{{ $toastVariants['success']['icon'] }}'"></span>
            <span class="text-sm font-semibold" x-text="toast.message"></span>
        </div>
    </template>
</div>
