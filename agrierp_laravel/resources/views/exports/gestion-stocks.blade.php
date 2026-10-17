<table class="data-table">
    <thead>
        <tr>
            <th>Code</th>
            <th>Désignation</th>
            <th>Catégorie</th>
            <th style="text-align:right;">Stock</th>
            <th style="text-align:right;">PMP Unit.</th>
            <th style="text-align:right;">Valeur</th>
            <th>Urgence</th>
        </tr>
    </thead>
    <tbody>
        @forelse($rows as $row)
            <tr>
                <td>{{ $row['product']->sku ?? '—' }}</td>
                <td>{{ $row['product']->name }}</td>
                <td>{{ $row['product']->category?->label ?? '—' }}</td>
                <td style="text-align:right;">{{ number_format($row['product']->stock_qty, 2, ',', ' ') }} {{ $row['product']->unit }}</td>
                <td style="text-align:right;">{{ $row['pmp'] !== null ? number_format($row['pmp'], 0, ',', ' ').' FCFA' : '—' }}</td>
                <td style="text-align:right;">{{ $row['valeur'] !== null ? number_format($row['valeur'], 0, ',', ' ').' FCFA' : '—' }}</td>
                <td>{{ $row['urgence'] ? 'Oui' : '—' }}</td>
            </tr>
        @empty
            <tr><td colspan="7" style="text-align:center;">Aucun produit ne correspond aux filtres actifs.</td></tr>
        @endforelse
    </tbody>
</table>
