<table class="data-table">
    <thead>
        <tr>
            <th>Date</th>
            <th style="text-align:right;">Solde Caisse</th>
            <th style="text-align:right;">Solde Banque</th>
            <th style="text-align:right;">Solde Total</th>
        </tr>
    </thead>
    <tbody>
        @forelse($rows as $r)
            <tr>
                <td>{{ \Carbon\Carbon::parse($r['date'])->format('d/m/Y') }}</td>
                <td style="text-align:right;">{{ number_format($r['caisse'], 0, ',', ' ') }}</td>
                <td style="text-align:right;">{{ number_format($r['banque'], 0, ',', ' ') }}</td>
                <td style="text-align:right;"><strong>{{ number_format($r['total'], 0, ',', ' ') }}</strong></td>
            </tr>
        @empty
            <tr><td colspan="4" style="text-align:center;">Aucun mouvement de trésorerie sur la période.</td></tr>
        @endforelse
    </tbody>
</table>
