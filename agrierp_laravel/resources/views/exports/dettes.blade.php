<table class="data-table">
    <thead>
        <tr>
            <th>Fournisseur</th>
            <th style="text-align:right;">Montant Dû</th>
            <th>Échéance</th>
        </tr>
    </thead>
    <tbody>
        @forelse($payables as $p)
            <tr>
                <td>{{ $p->supplier?->name ?? '—' }}</td>
                <td style="text-align:right;">{{ number_format($p->balance, 0, ',', ' ') }} FCFA</td>
                <td>{{ $p->due_date->format('d/m/Y') }}</td>
            </tr>
        @empty
            <tr><td colspan="3" style="text-align:center;">Aucune dette sur la période.</td></tr>
        @endforelse
    </tbody>
</table>
