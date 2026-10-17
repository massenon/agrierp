<table class="data-table">
    <thead>
        <tr>
            <th>Bande</th><th>Espèce</th><th>Dernière Pesée</th>
            <th style="text-align:right;">Poids Précédent (g)</th>
            <th style="text-align:right;">Poids Actuel (g)</th>
            <th style="text-align:right;">Jours</th>
            <th style="text-align:right;">GMQ (g/j)</th>
            <th>Statut vs Objectif</th>
        </tr>
    </thead>
    <tbody>
        @forelse($rows as $row)
            <tr>
                <td>{{ $row['lot_code'] }}</td>
                <td>{{ $row['species_label'] }}</td>
                <td>{{ \Carbon\Carbon::parse($row['date_pesee'])->format('d/m/Y') }}</td>
                <td style="text-align:right;">{{ number_format($row['poids_precedent'], 0, ',', ' ') }}</td>
                <td style="text-align:right;">{{ number_format($row['poids_actuel'], 0, ',', ' ') }}</td>
                <td style="text-align:right;">{{ $row['jours'] }}</td>
                <td style="text-align:right;">{{ $row['gmq'] }}</td>
                <td>
                    @switch($row['statut'])
                        @case('sous_objectif') Sous objectif @break
                        @case('au_dessus') Au-dessus objectif @break
                        @case('dans_cible') Dans la cible @break
                        @default Objectif non défini
                    @endswitch
                </td>
            </tr>
        @empty
            <tr><td colspan="8" style="text-align:center;">Aucun lot avec au moins deux pesées.</td></tr>
        @endforelse
    </tbody>
</table>
<p style="font-size:11px;margin-top:10px;">GMQ calculé entre les deux dernières pesées de chaque bande. Objectifs issus du référentiel paramétrable des standards de croissance.</p>
