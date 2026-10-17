<table class="data-table">
    <thead>
        <tr>
            <th>Fournisseur</th>
            <th style="text-align:right;">Montant Dû</th>
            <th>Échéance</th>
            <th>Statut</th>
        </tr>
    </thead>
    <tbody>
        @php
            $statusLabels = ['soldee' => 'Réglé', 'en_retard' => 'En retard', 'en_cours' => 'À échoir'];
        @endphp
        @forelse($debts as $debt)
            <tr>
                <td>{{ $debt->supplier?->name ?? '—' }}</td>
                <td style="text-align:right;">{{ number_format($debt->balance, 0, ',', ' ') }} FCFA</td>
                <td>{{ $debt->due_date?->format('d/m/Y') ?? '—' }}</td>
                <td>{{ $statusLabels[$debt->display_status] ?? $debt->display_status }}</td>
            </tr>
        @empty
            <tr><td colspan="4" style="text-align:center;">Aucune dette fournisseur pour le moment.</td></tr>
        @endforelse
    </tbody>
</table>
