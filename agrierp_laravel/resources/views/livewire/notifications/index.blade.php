<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">notifications</span>Centre de Notifications
        </h2>
        <p class="text-xs text-outline mt-xs">Toutes les alertes et notifications système d'LogiAgriERP.</p>
    </div>

    <x-kpi-accordion title="Résumé des alertes">
        <x-kpi-card label="Non Lues" icon="mark_email_unread" color="red" :value="$this->kpis['non_lues']" />
        <x-kpi-card label="Critiques" icon="warning" color="maize" :value="$this->kpis['critiques']" />
        <x-kpi-card label="Total (30 jours)" icon="notifications" color="emerald" :value="$this->kpis['total_30_jours']" />
    </x-kpi-accordion>

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-md flex flex-wrap items-center gap-sm">
        <div class="relative flex-1 min-w-[180px]">
            <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
            <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher un message..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
        </div>
        <select wire:model.live="category" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">Toutes catégories</option>
            <option>Élevage</option><option>Stocks</option><option>Finance</option><option>RH</option>
        </select>
        <select wire:model.live="statut" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">Toutes</option>
            <option>Non lue</option><option>Lue</option>
        </select>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        @if($this->notifications->isEmpty())
            <p class="text-xs text-outline text-center py-xl">Aucune notification pour le moment.</p>
        @else
            <div class="overflow-x-auto">
                <table class="w-full rtable">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date / Heure</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Catégorie</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Message</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Gravité</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach($this->notifications as $i => $notif)
                            <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                <td data-label="Date" class="px-md py-sm text-xs whitespace-nowrap">{{ $notif->created_at->format('d/m/Y - H:i') }}</td>
                                <td data-label="Catégorie" class="px-md py-sm">
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">{{ $notif->category }}</span>
                                </td>
                                <td data-label="Message" class="px-md py-sm text-xs max-w-xs">{{ $notif->message }}</td>
                                <td data-label="Gravité" class="px-md py-sm">
                                    @if($notif->severity === 'critique')
                                        <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-bg text-error-deep border-error-deep/30">Critique</span>
                                    @elseif($notif->severity === 'moyen')
                                        <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">Moyen</span>
                                    @else
                                        <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-surface-zebra text-outline border-outline-variant">Info</span>
                                    @endif
                                </td>
                                <td data-label="Statut" class="px-md py-sm text-xs font-bold {{ $notif->is_read ? 'text-brand-emerald' : 'text-error-deep' }}">{{ $notif->is_read ? 'Lue' : 'Non lue' }}</td>
                                <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                    @if(!$notif->is_read)
                                        <button type="button" wire:click="markAsRead('{{ $notif->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="Marquer comme lue"><span class="material-symbols-outlined text-[18px]">check_circle</span></button>
                                    @endif
                                    @if($notif->link_url)
                                        <a href="{{ $notif->link_url }}" class="text-info-blue hover:text-blue-800 p-1 inline-block" title="Résoudre"><span class="material-symbols-outlined text-[18px]">arrow_forward</span></a>
                                    @endif
                                    <button type="button" wire:click="delete('{{ $notif->id }}')" wire:confirm="Supprimer cette notification ?" class="text-outline hover:text-error-red p-1" title="Supprimer"><span class="material-symbols-outlined text-[18px]">delete</span></button>
                                </td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        @endif
    </div>
</div>
