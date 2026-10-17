<div class="mt-md">
    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Solde Caisse</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Solde Banque</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Solde Total</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->rows as $i => $row)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Date" class="px-md py-sm text-xs">{{ \Carbon\Carbon::parse($row['date'])->format('d/m/Y') }}</td>
                            <td data-label="Solde Caisse" class="px-md py-sm text-xs">{{ number_format($row['caisse'], 0, ',', ' ') }}</td>
                            <td data-label="Solde Banque" class="px-md py-sm text-xs">{{ number_format($row['banque'], 0, ',', ' ') }}</td>
                            <td data-label="Solde Total" class="px-md py-sm text-xs font-bold">{{ number_format($row['total'], 0, ',', ' ') }}</td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <span class="text-outline text-[10px] italic" title="Ce rapport est généré à partir des écritures comptables réelles ; il ne peut pas être modifié ici.">Lecture seule</span>
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="5" class="px-md py-lg text-center text-outline">Aucun mouvement de trésorerie sur la période.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
</div>
