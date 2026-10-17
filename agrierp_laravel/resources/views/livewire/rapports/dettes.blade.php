<div class="mt-md">
    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md border-b border-outline-variant">
            <div class="relative max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
            </div>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Fournisseur</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Montant Dû</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Échéance</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->payables as $i => $p)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Fournisseur" class="px-md py-sm text-xs">{{ $p->supplier?->name ?? '—' }}</td>
                            <td data-label="Montant Dû" class="px-md py-sm text-xs font-bold">{{ number_format($p->balance, 0, ',', ' ') }}</td>
                            <td data-label="Échéance" class="px-md py-sm text-xs">{{ $p->due_date->format('d/m/Y') }}</td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <span class="text-outline text-[10px] italic" title="Ce rapport est généré à partir des données réelles ; il ne peut pas être modifié ici.">Lecture seule</span>
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="4" class="px-md py-lg text-center text-outline">Aucune dette sur la période.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
</div>
