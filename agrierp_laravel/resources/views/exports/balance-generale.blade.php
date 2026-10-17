<table class="data-table">
    <thead>
        <tr>
            <th>N° Compte</th>
            <th>Libellé</th>
            <th style="text-align:right;">Ouv. Débit</th>
            <th style="text-align:right;">Ouv. Crédit</th>
            <th style="text-align:right;">Mvt Débit</th>
            <th style="text-align:right;">Mvt Crédit</th>
            <th style="text-align:right;">Final Débit</th>
            <th style="text-align:right;">Final Crédit</th>
        </tr>
    </thead>
    <tbody>
        @forelse($balance['rows'] as $row)
            <tr>
                <td>{{ $row['code'] }}</td>
                <td>{{ $row['label'] }}</td>
                <td style="text-align:right;">{{ $row['opening_debit'] > 0 ? number_format($row['opening_debit'], 0, ',', ' ') : '—' }}</td>
                <td style="text-align:right;">{{ $row['opening_credit'] > 0 ? number_format($row['opening_credit'], 0, ',', ' ') : '—' }}</td>
                <td style="text-align:right;">{{ $row['period_debit'] > 0 ? number_format($row['period_debit'], 0, ',', ' ') : '—' }}</td>
                <td style="text-align:right;">{{ $row['period_credit'] > 0 ? number_format($row['period_credit'], 0, ',', ' ') : '—' }}</td>
                <td style="text-align:right;">{{ $row['final_debit'] > 0 ? number_format($row['final_debit'], 0, ',', ' ') : '—' }}</td>
                <td style="text-align:right;">{{ $row['final_credit'] > 0 ? number_format($row['final_credit'], 0, ',', ' ') : '—' }}</td>
            </tr>
        @empty
            <tr><td colspan="8" style="text-align:center;">Aucun compte mouvementé sur cette période.</td></tr>
        @endforelse
        <tr>
            <td colspan="2"><strong>TOTAUX</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($balance['total_opening_debit'], 0, ',', ' ') }}</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($balance['total_opening_credit'], 0, ',', ' ') }}</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($balance['total_period_debit'], 0, ',', ' ') }}</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($balance['total_period_credit'], 0, ',', ' ') }}</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($balance['total_final_debit'], 0, ',', ' ') }}</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($balance['total_final_credit'], 0, ',', ' ') }}</strong></td>
        </tr>
    </tbody>
</table>

@unless($balance['is_balanced'])
    <p style="margin-top:12px;color:#BA1A1A;font-weight:bold;">
        Balance déséquilibrée — écart de {{ number_format($balance['ecart'], 0, ',', ' ') }} FCFA.
        Une anomalie de saisie doit être corrigée avant toute clôture.
    </p>
@endunless
