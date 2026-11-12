<div class="mt-md">
    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('rapports.creances_col_client') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('rapports.creances_col_montant_du') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('rapports.creances_col_echeance') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('rapports.creances_col_actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->receivables as $i => $r)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Client" class="px-md py-sm text-xs">{{ $r->customer?->name ?? '—' }}</td>
                            <td data-label="Montant Dû" class="px-md py-sm text-xs font-bold">{{ number_format($r->balance, 0, ',', ' ') }}</td>
                            <td data-label="Échéance" class="px-md py-sm text-xs">{{ $r->due_date->format('d/m/Y') }}</td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <span class="text-outline text-[10px] italic" title="{{ __('rapports.creances_lecture_seule_title') }}">{{ __('rapports.creances_lecture_seule') }}</span>
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="4" class="px-md py-lg text-center text-outline">{{ __('rapports.creances_vide') }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
</div>
