<table class="data-table">
    <thead>
        <tr>
            <th>Client</th>
            <th style="text-align:right;">Montant Avance</th>
            <th style="text-align:right;">Solde Restant</th>
            <th>Date</th>
            <th>Statut</th>
        </tr>
    </thead>
    <tbody>
        @forelse($advances as $advance)
            <tr>
                <td>{{ $advance->customer?->name ?? '—' }}</td>
                <td style="text-align:right;">{{ number_format($advance->amount, 0, ',', ' ') }} FCFA</td>
                <td style="text-align:right;">{{ number_format($advance->remaining, 0, ',', ' ') }} FCFA</td>
                <td>{{ $advance->advance_date->format('d/m/Y') }}</td>
                <td>{{ $advance->remaining > 0 ? 'En cours' : 'Soldée' }}</td>
            </tr>
        @empty
            <tr><td colspan="5" style="text-align:center;">Aucune avance enregistrée.</td></tr>
        @endforelse
    </tbody>
</table>
