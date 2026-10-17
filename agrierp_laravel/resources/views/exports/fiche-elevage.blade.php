<table class="data-table">
    <thead>
        <tr>
            <th>Date</th>
            <th style="text-align:right;">Achat</th>
            <th style="text-align:right;">Nés</th>
            <th style="text-align:right;">Morts</th>
            <th style="text-align:right;">Ventes</th>
            <th style="text-align:right;">Dons</th>
            <th style="text-align:right;">Effectif Final</th>
            <th style="text-align:right;">Mortalité</th>
        </tr>
    </thead>
    <tbody>
        @forelse($entries as $entry)
            <tr>
                <td>{{ $entry->entry_date->format('d/m/Y') }}</td>
                <td style="text-align:right;">{{ $entry->achat }}</td>
                <td style="text-align:right;">{{ $entry->ne }}</td>
                <td style="text-align:right;">{{ $entry->mort }}</td>
                <td style="text-align:right;">{{ $entry->vente }}</td>
                <td style="text-align:right;">{{ $entry->don }}</td>
                <td style="text-align:right;">{{ $entry->effectif_final }}</td>
                <td style="text-align:right;">{{ number_format($entry->mortality_rate, 1, ',', ' ') }}%</td>
            </tr>
        @empty
            <tr><td colspan="8" style="text-align:center;">Aucune saisie ce mois-ci.</td></tr>
        @endforelse
    </tbody>
</table>
