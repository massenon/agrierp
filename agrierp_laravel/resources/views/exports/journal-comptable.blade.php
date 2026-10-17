<table class="data-table">
    <thead>
        <tr>
            <th>N° Pièce</th>
            <th>Date</th>
            <th>Libellé</th>
            <th>Débit</th>
            <th>Crédit</th>
            <th style="text-align:right;">Montant</th>
        </tr>
    </thead>
    <tbody>
        @forelse($entries as $entry)
            @php
                $refParts = explode('—', (string) $entry->reference, 2);
                $piece = trim($refParts[0] ?? '');
                $label = trim($refParts[1] ?? '');
                $debitLine = $component->debitLine($entry);
                $creditLine = $component->creditLine($entry);
            @endphp
            <tr>
                <td>{{ $piece }}</td>
                <td>{{ $entry->entry_date->format('d/m/Y') }}</td>
                <td>{{ $label }}</td>
                <td>{{ $debitLine?->account?->code }} - {{ $debitLine?->account?->label }}</td>
                <td>{{ $creditLine?->account?->code }} - {{ $creditLine?->account?->label }}</td>
                <td style="text-align:right;">{{ number_format($entry->total_debit, 0, ',', ' ') }} FCFA</td>
            </tr>
        @empty
            <tr><td colspan="6" style="text-align:center;">Aucune écriture pour le moment.</td></tr>
        @endforelse
    </tbody>
</table>
