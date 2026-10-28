<div wire:poll.30s x-data="{ open: false }" class="relative" @click.outside="open = false">
    <button type="button" dusk="notification-bell" @click="open = !open" class="text-outline hover:text-brand-emerald relative">
        <span class="material-symbols-outlined">notifications</span>
        @if($this->unreadCount > 0)
            <span class="absolute -top-1 -right-1 flex h-4 w-4">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-error-red opacity-75"></span>
                <span class="relative inline-flex rounded-full h-4 w-4 bg-error-red text-white text-[9px] font-bold items-center justify-center">{{ $this->unreadCount > 9 ? '9+' : $this->unreadCount }}</span>
            </span>
        @endif
    </button>
    <div x-show="open" x-cloak class="absolute right-0 mt-sm w-80 bg-white border border-outline-variant rounded-lg shadow-lg z-50 overflow-hidden">
        <div class="flex items-center justify-between px-md py-sm border-b border-outline-variant">
            <span class="font-bold text-xs text-brand-forest">Notifications</span>
        </div>
        <div class="max-h-64 overflow-y-auto">
            @forelse($this->recent as $notif)
                <div wire:key="bell-{{ $notif->id }}" class="notif-item px-md py-sm border-b border-outline-variant hover:bg-surface-zebra flex items-start justify-between gap-xs">
                    <div class="min-w-0">
                        <p class="text-xs font-semibold {{ $notif->is_read ? 'text-on-surface' : 'text-error-deep' }}">{{ $notif->title }}</p>
                        <p class="text-[10px] text-outline">{{ $notif->created_at->diffForHumans() }}</p>
                    </div>
                    @if(!$notif->is_read)
                        <button type="button" wire:click="markAsRead('{{ $notif->id }}')" class="text-brand-emerald hover:text-brand-forest flex-shrink-0" title="Marquer comme lue">
                            <span class="material-symbols-outlined text-[16px]">check_circle</span>
                        </button>
                    @endif
                </div>
            @empty
                <p class="text-[11px] text-outline text-center py-lg">Aucune notification pour le moment.</p>
            @endforelse
        </div>
        <a wire:navigate href="/notifications" class="block text-center py-sm text-xs font-bold text-brand-emerald hover:bg-surface-zebra border-t border-outline-variant">Voir toutes les notifications</a>
    </div>
</div>
