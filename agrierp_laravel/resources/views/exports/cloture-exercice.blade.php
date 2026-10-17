<div style="margin-bottom: 12px;">
    <p><strong>Exercice :</strong> {{ $fiscalYear?->year ?? '—' }}</p>
    <p><strong>Résultat Provisoire :</strong> {{ number_format($kpis['resultat'], 0, ',', ' ') }} FCFA</p>
    <p><strong>Comptes de Gestion à Solder :</strong> {{ $kpis['comptes_a_solder'] }}</p>
</div>

<table class="data-table">
    <thead>
        <tr>
            <th>Compte</th>
            <th>Intitulé</th>
            <th>Classe</th>
            <th style="text-align:right;">Solde</th>
        </tr>
    </thead>
    <tbody>
        @forelse($rows as $row)
            <tr>
                <td>{{ $row['code'] }}</td>
                <td>{{ $row['label'] }}</td>
                <td>{{ $row['class'] }}</td>
                <td style="text-align:right;">{{ number_format($row['balance'], 0, ',', ' ') }} FCFA</td>
            </tr>
        @empty
            <tr><td colspan="4" style="text-align:center;">Aucun compte de gestion à solder.</td></tr>
        @endforelse
    </tbody>
</table>
