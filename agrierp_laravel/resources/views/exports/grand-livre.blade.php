<table class="data-table">
    <thead>
        <tr>
            <th>Date</th>
            <th>N° Pièce</th>
            <th>Libellé</th>
            <th style="text-align:right;">Débit</th>
            <th style="text-align:right;">Crédit</th>
            <th style="text-align:right;">Solde Progressif</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td colspan="5"><strong>Solde d'ouverture</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($ledger['opening_balance'], 0, ',', ' ') }} FCFA</strong></td>
        </tr>
        @forelse($ledger['lines'] as $line)
            <tr>
                <td>{{ \Carbon\Carbon::parse($line['date'])->format('d/m/Y') }}</td>
                <td>{{ $line['reference'] }}</td>
                <td>{{ $line['label'] }}</td>
                <td style="text-align:right;">{{ $line['debit'] > 0 ? number_format($line['debit'], 0, ',', ' ') : '—' }}</td>
                <td style="text-align:right;">{{ $line['credit'] > 0 ? number_format($line['credit'], 0, ',', ' ') : '—' }}</td>
                <td style="text-align:right;">{{ number_format($line['running_balance'], 0, ',', ' ') }}</td>
            </tr>
        @empty
            <tr><td colspan="6" style="text-align:center;">Aucune écriture ne correspond à ces critères.</td></tr>
        @endforelse
        <tr>
            <td colspan="3"><strong>Totaux de la période</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($ledger['total_debit'], 0, ',', ' ') }}</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($ledger['total_credit'], 0, ',', ' ') }}</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($ledger['closing_balance'], 0, ',', ' ') }}</strong></td>
        </tr>
    </tbody>
</table>
