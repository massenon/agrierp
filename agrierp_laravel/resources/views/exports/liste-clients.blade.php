<table class="data-table">
    <thead>
        <tr>
            <th>Nom</th>
            <th>Téléphone</th>
            <th>Ville</th>
            <th style="text-align:right;">Total Achats</th>
            <th style="text-align:right;">Solde Dû</th>
            <th>Statut</th>
        </tr>
    </thead>
    <tbody>
        @forelse($rows as $row)
            <tr>
                <td>{{ $row['customer']->name }}</td>
                <td>{{ $row['customer']->phone ?? '—' }}</td>
                <td>{{ $row['customer']->city ?? '—' }}</td>
                <td style="text-align:right;">{{ number_format($row['total_achats'], 0, ',', ' ') }} FCFA</td>
                <td style="text-align:right;">{{ number_format($row['solde_du'], 0, ',', ' ') }} FCFA</td>
                <td>{{ $row['statut'] }}</td>
            </tr>
        @empty
            <tr><td colspan="6" style="text-align:center;">Aucun client ne correspond aux filtres actifs.</td></tr>
        @endforelse
    </tbody>
</table>
