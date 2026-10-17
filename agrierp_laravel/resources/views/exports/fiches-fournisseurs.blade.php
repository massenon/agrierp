<table class="data-table">
    <thead>
        <tr>
            <th>Nom</th>
            <th>Catégorie</th>
            <th style="text-align:right;">Total Achats (Année)</th>
            <th>Dernière commande</th>
            <th>Statut</th>
        </tr>
    </thead>
    <tbody>
        @forelse($suppliers as $supplier)
            <tr>
                <td>{{ $supplier->name }}</td>
                <td>{{ $supplier->category ?? '—' }}</td>
                <td style="text-align:right;">{{ number_format($supplier->total_achats_annee, 0, ',', ' ') }} FCFA</td>
                <td>{{ $supplier->derniere_commande?->format('d/m/Y') ?? '—' }}</td>
                <td>{{ $supplier->is_active ? 'Actif' : 'Inactif' }}</td>
            </tr>
        @empty
            <tr><td colspan="5" style="text-align:center;">Aucun fournisseur ne correspond aux filtres actifs.</td></tr>
        @endforelse
    </tbody>
</table>
