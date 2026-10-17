<p><strong>Référence :</strong> {{ strtoupper(substr($sale->id, 0, 8)) }}</p>
<p><strong>Client :</strong> {{ $sale->customer?->name ?? 'Client Anonyme' }}</p>
<p><strong>Date :</strong> {{ $sale->date_effective->format('d/m/Y H:i') }}</p>

<table class="data-table" style="margin-top: 12px;">
    <thead>
        <tr>
            <th>Désignation</th>
            <th style="text-align:right;">Qté</th>
            <th style="text-align:right;">P.U</th>
            <th style="text-align:right;">Total</th>
        </tr>
    </thead>
    <tbody>
        @foreach($sale->lines as $line)
            <tr>
                <td>{{ $line->product?->name }}</td>
                <td style="text-align:right;">{{ rtrim(rtrim(number_format($line->qty, 2, '.', ''), '0'), '.') }}</td>
                <td style="text-align:right;">{{ number_format($line->unit_price, 0, ',', ' ') }}</td>
                <td style="text-align:right;">{{ number_format($line->manual_total_amount, 0, ',', ' ') }}</td>
            </tr>
        @endforeach
    </tbody>
</table>

<div style="margin-top: 12px; text-align: right;">
    <p>Sous-total : {{ number_format($sale->subtotal, 0, ',', ' ') }} FCFA</p>
    <p>Remise : {{ number_format($sale->discount, 0, ',', ' ') }} FCFA</p>
    <p><strong>Total TTC : {{ number_format($sale->total, 0, ',', ' ') }} FCFA</strong></p>
</div>

<p style="margin-top: 20px; text-align: center; font-size: 9px;">Document généré par AgriERP — Ferme École OLOUWACHEGOUN</p>
