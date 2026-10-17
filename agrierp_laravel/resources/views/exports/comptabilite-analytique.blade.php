<div style="margin-bottom: 12px;">
    <p><strong>Chiffre d'Affaires Analytique :</strong> {{ number_format($kpis['ca'], 0, ',', ' ') }} FCFA</p>
    <p><strong>Charges Directes :</strong> {{ number_format($kpis['charges'], 0, ',', ' ') }} FCFA</p>
    <p><strong>Marge Brute Opérationnelle :</strong> {{ number_format($kpis['marge'], 0, ',', ' ') }} FCFA</p>
    <p><strong>Taux de Rentabilité :</strong> {{ $kpis['taux'] !== null ? $kpis['taux'].' %' : '—' }}</p>
</div>

<table class="data-table">
    <thead>
        <tr>
            <th>Filière</th>
            <th style="text-align:right;">CA (FCFA)</th>
            <th style="text-align:right;">Charges (FCFA)</th>
            <th style="text-align:right;">Marge (FCFA)</th>
            <th style="text-align:right;">Taux</th>
        </tr>
    </thead>
    <tbody>
        @forelse($rows as $row)
            <tr>
                <td>{{ $row['filiere']->label }}</td>
                <td style="text-align:right;">{{ number_format($row['ca'], 0, ',', ' ') }}</td>
                <td style="text-align:right;">{{ number_format($row['charges'], 0, ',', ' ') }}</td>
                <td style="text-align:right;">{{ number_format($row['marge'], 0, ',', ' ') }}</td>
                <td style="text-align:right;">{{ $row['taux'] !== null ? $row['taux'].' %' : '—' }}</td>
            </tr>
        @empty
            <tr><td colspan="5" style="text-align:center;">Aucune filière active.</td></tr>
        @endforelse
    </tbody>
</table>
