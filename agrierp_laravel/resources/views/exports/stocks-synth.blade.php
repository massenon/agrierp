<table class="data-table">
    <thead>
        <tr>
            <th>Catégorie</th>
            <th style="text-align:right;">Valeur Stock</th>
            <th style="text-align:center;">Sous Seuil</th>
        </tr>
    </thead>
    <tbody>
        @forelse($rows as $r)
            <tr>
                <td>{{ $r['category']->label }}</td>
                <td style="text-align:right;">{{ number_format($r['valeur_stock'], 0, ',', ' ') }} FCFA</td>
                <td style="text-align:center;">{{ $r['sous_seuil'] }}</td>
            </tr>
        @empty
            <tr><td colspan="3" style="text-align:center;">Aucune catégorie active.</td></tr>
        @endforelse
    </tbody>
</table>
