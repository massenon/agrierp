<table class="data-table">
    <thead>
        <tr>
            <th>Débiteur</th>
            <th>Facture</th>
            <th>Échéance</th>
            <th style="text-align:right;">Total Facturé</th>
            <th style="text-align:right;">Solde Restant</th>
        </tr>
    </thead>
    <tbody>
        @forelse($debts as $debt)
            <tr>
                <td>{{ $debt->customer?->name ?? '—' }}</td>
                <td>{{ strtoupper(substr($debt->sale_id ?? $debt->id, 0, 8)) }}</td>
                <td>{{ $debt->due_date?->format('d/m/Y') ?? '—' }}</td>
                <td style="text-align:right;">{{ number_format($debt->amount, 0, ',', ' ') }} FCFA</td>
                <td style="text-align:right;">{{ number_format($debt->balance, 0, ',', ' ') }} FCFA</td>
            </tr>
        @empty
            <tr><td colspan="5" style="text-align:center;">Aucune créance en cours.</td></tr>
        @endforelse
    </tbody>
</table>
