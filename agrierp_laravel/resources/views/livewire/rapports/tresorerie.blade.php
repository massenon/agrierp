<div class="mt-md">
    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('rapports.tresorerie_col_date') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('rapports.tresorerie_col_caisse') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('rapports.tresorerie_col_banque') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('rapports.tresorerie_col_total') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('rapports.tresorerie_col_actions') }}</th>
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
                                <span class="text-outline text-[10px] italic" title="{{ __('rapports.tresorerie_lecture_seule_title') }}">{{ __('rapports.tresorerie_lecture_seule') }}</span>
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="5" class="px-md py-lg text-center text-outline">{{ __('rapports.tresorerie_vide') }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
</div>
