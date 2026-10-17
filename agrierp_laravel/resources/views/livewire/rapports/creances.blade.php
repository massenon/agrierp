<div class="mt-md">
    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Client</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Montant Dû</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Échéance</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->receivables as $i => $r)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Client" class="px-md py-sm text-xs">{{ $r->customer?->name ?? '—' }}</td>
                            <td data-label="Montant Dû" class="px-md py-sm text-xs font-bold">{{ number_format($r->balance, 0, ',', ' ') }}</td>
                            <td data-label="Échéance" class="px-md py-sm text-xs">{{ $r->due_date->format('d/m/Y') }}</td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <span class="text-outline text-[10px] italic" title="Ce rapport est généré à partir des données réelles ; il ne peut pas être modifié ici.">Lecture seule</span>
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="4" class="px-md py-lg text-center text-outline">Aucune créance sur la période.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
</div>
