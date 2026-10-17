<table class="data-table">
    <thead>
        <tr>
            <th>Référence Achat</th>
            <th>Date</th>
            <th>Fournisseur</th>
            <th>Catégorie</th>
            <th style="text-align:right;">Montant Total</th>
            <th>Statut</th>
        </tr>
    </thead>
    <tbody>
        @forelse($purchases as $purchase)
            <tr>
                <td>{{ strtoupper(substr($purchase->id, 0, 8)) }}</td>
                <td>{{ $purchase->purchase_date->format('d/m/Y') }}</td>
                <td>{{ $purchase->supplier?->name ?? '—' }}</td>
                <td>{{ $purchase->categorie }}</td>
                <td style="text-align:right;">{{ number_format($purchase->total, 0, ',', ' ') }} FCFA</td>
                <td>{{ $purchase->is_dette ? 'Dette fournisseur' : 'Payé entièrement' }}</td>
            </tr>
        @empty
            <tr><td colspan="6" style="text-align:center;">Aucun achat ne correspond aux filtres actifs.</td></tr>
        @endforelse
    </tbody>
</table>
