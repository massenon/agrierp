<div class="mt-md">
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-md mb-lg">
        <x-kpi-card label="Total Recettes" icon="trending_up" color="emerald" :value="number_format($this->kpis['recettes'], 0, ',', ' ').' F'" />
        <x-kpi-card label="Total Dépenses" icon="trending_down" color="red" :value="number_format($this->kpis['depenses'], 0, ',', ' ').' F'" />
        <x-kpi-card label="Solde Net" icon="account_balance_wallet" color="blue" :value="number_format($this->kpis['solde'], 0, ',', ' ').' F'" />
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-md">
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <div class="px-md py-sm border-b border-outline-variant bg-brand-emerald/5"><h3 class="text-sm font-bold text-brand-emerald">Recettes</h3></div>
            <table class="w-full text-xs">
                <thead><tr class="text-outline border-b border-outline-variant"><th class="text-left px-md py-sm">Date</th><th class="text-left px-md py-sm">Libellé</th><th class="text-right px-md py-sm">Montant</th></tr></thead>
                <tbody>
                    @forelse($this->recettes as $i => $r)
                        <tr class="{{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} border-b border-outline-variant">
                            <td class="px-md py-sm text-xs">{{ \Carbon\Carbon::parse($r['date'])->format('d/m/Y') }}</td>
                            <td class="px-md py-sm text-xs">{{ $r['label'] }}</td>
                            <td class="px-md py-sm text-xs text-right font-bold text-brand-emerald">+{{ number_format($r['amount'], 0, ',', ' ') }} FCFA</td>
                        </tr>
                    @empty
                        <tr><td colspan="3" class="px-md py-lg text-center text-outline">Aucune recette sur la période.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <div class="px-md py-sm border-b border-outline-variant bg-error-bg"><h3 class="text-sm font-bold text-error-deep">Dépenses</h3></div>
            <table class="w-full text-xs">
                <thead><tr class="text-outline border-b border-outline-variant"><th class="text-left px-md py-sm">Date</th><th class="text-left px-md py-sm">Libellé</th><th class="text-right px-md py-sm">Montant</th></tr></thead>
                <tbody>
                    @forelse($this->depenses as $i => $d)
                        <tr class="{{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} border-b border-outline-variant">
                            <td class="px-md py-sm text-xs">{{ \Carbon\Carbon::parse($d['date'])->format('d/m/Y') }}</td>
                            <td class="px-md py-sm text-xs">{{ $d['label'] }}</td>
                            <td class="px-md py-sm text-xs text-right font-bold text-error-deep">-{{ number_format($d['amount'], 0, ',', ' ') }} FCFA</td>
                        </tr>
                    @empty
                        <tr><td colspan="3" class="px-md py-lg text-center text-outline">Aucune dépense sur la période.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
</div>
