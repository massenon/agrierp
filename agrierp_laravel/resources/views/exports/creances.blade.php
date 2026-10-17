<table class="data-table">
    <thead>
        <tr>
            <th>Client</th>
            <th style="text-align:right;">Montant Dû</th>
            <th>Échéance</th>
        </tr>
    </thead>
    <tbody>
        @forelse($receivables as $r)
            <tr>
                <td>{{ $r->customer?->name ?? '—' }}</td>
                <td style="text-align:right;">{{ number_format($r->balance, 0, ',', ' ') }} FCFA</td>
                <td>{{ $r->due_date->format('d/m/Y') }}</td>
            </tr>
        @empty
            <tr><td colspan="3" style="text-align:center;">Aucune créance sur la période.</td></tr>
        @endforelse
    </tbody>
</table>
