<table class="data-table">
    <thead>
        <tr>
            <th>N° Devis</th>
            <th>Client</th>
            <th>Date</th>
            <th style="text-align:right;">Montant</th>
            <th>Statut</th>
        </tr>
    </thead>
    <tbody>
        @php
            $statusLabels = ['brouillon' => 'Brouillon', 'envoye' => 'Envoyé', 'accepte' => 'Accepté', 'refuse' => 'Refusé', 'facture' => 'Facturé'];
        @endphp
        @forelse($quotes as $quote)
            <tr>
                <td>{{ $quote->quote_number }}</td>
                <td>{{ $quote->customer?->name ?? '—' }}</td>
                <td>{{ $quote->quote_date->format('d/m/Y') }}</td>
                <td style="text-align:right;">{{ number_format($quote->amount, 0, ',', ' ') }} FCFA</td>
                <td>{{ $statusLabels[$quote->status] ?? $quote->status }}</td>
            </tr>
        @empty
            <tr><td colspan="5" style="text-align:center;">Aucun devis ne correspond aux filtres actifs.</td></tr>
        @endforelse
    </tbody>
</table>
