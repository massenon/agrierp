<table style="width:100%; border-collapse: collapse; font-size: 9px; margin-bottom: 12px;">
    <tr>
        <td style="width:50%; vertical-align: top; padding: 6px; border: 1px solid #bec9c2;">
            <strong>Fournisseur</strong><br>
            {{ $purchaseOrder->supplier?->name }}<br>
            @if($purchaseOrder->supplier?->phone) Tél : {{ $purchaseOrder->supplier->phone }}<br> @endif
            @if($purchaseOrder->supplier?->email) {{ $purchaseOrder->supplier->email }} @endif
        </td>
        <td style="width:50%; vertical-align: top; padding: 6px; border: 1px solid #bec9c2;">
            <strong>Référence</strong> : {{ strtoupper(substr($purchaseOrder->id, 0, 8)) }}<br>
            <strong>Date d'émission</strong> : {{ $purchaseOrder->created_at->format('d/m/Y') }}<br>
            <strong>Livraison attendue</strong> : {{ $purchaseOrder->expected_delivery_date?->format('d/m/Y') ?? '—' }}<br>
            <strong>Statut</strong> : {{ $statusLabel }}
        </td>
    </tr>
</table>

<table class="data-table">
    <thead>
        <tr>
            <th>Produit / Article</th>
            <th style="text-align:right;">Quantité</th>
            <th style="text-align:right;">P.U. Estimé (FCFA)</th>
            <th style="text-align:right;">Total (FCFA)</th>
        </tr>
    </thead>
    <tbody>
        @foreach($purchaseOrder->lines as $line)
            <tr>
                <td>{{ $line->product?->name }}</td>
                <td style="text-align:right;">{{ rtrim(rtrim(number_format($line->qty, 2, '.', ''), '0'), '.') }} {{ $line->product?->unit }}</td>
                <td style="text-align:right;">{{ number_format($line->estimated_unit_price, 0, ',', ' ') }}</td>
                <td style="text-align:right;">{{ number_format($line->qty * $line->estimated_unit_price, 0, ',', ' ') }}</td>
            </tr>
        @endforeach
    </tbody>
</table>

<table style="width:100%; margin-top: 10px;">
    <tr>
        <td style="width:60%;"></td>
        <td style="width:40%; border: 1px solid #052e16; padding: 8px; text-align:right; font-weight:bold; font-size: 11px;">
            TOTAL ESTIMÉ : {{ number_format($total, 0, ',', ' ') }} FCFA
        </td>
    </tr>
</table>

<p style="margin-top:20px; font-size:8.5px; color:#6f7973;">
    Ce bon de commande est un ordre d'achat prévisionnel — les montants sont estimatifs et seront confirmés à la réception effective des marchandises.
</p>
