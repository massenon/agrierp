{{-- Facture d'une vente (Facturation) — avec ou sans certification MeCeF. --}}
<p style="font-size:12px;">
    Facture <strong>{{ $sale->numero_facture }}</strong> du <strong>{{ $sale->date_effective->format('d/m/Y') }}</strong><br>
    Client : <strong>{{ $sale->customer?->name ?? 'Client Anonyme' }}</strong>
    @if($sale->customer?->phone) — {{ $sale->customer->phone }} @endif
    <br>Mode de règlement : {{ $sale->payment_mode ?? '—' }}
</p>

<table class="data-table">
    <thead>
        <tr>
            <th>Désignation</th>
            <th style="text-align:right;">Quantité</th>
            <th style="text-align:right;">Prix unitaire</th>
            <th style="text-align:right;">Montant</th>
        </tr>
    </thead>
    <tbody>
        @forelse($sale->lines as $ligne)
            @php $montant = $ligne->manual_total_amount ?? ($ligne->qty * $ligne->unit_price); @endphp
            <tr>
                <td>{{ $ligne->product?->name ?? '—' }}</td>
                <td style="text-align:right;">{{ rtrim(rtrim(number_format($ligne->qty, 2, ',', ' '), '0'), ',') }}</td>
                <td style="text-align:right;">{{ number_format($ligne->qty > 0 ? $montant / $ligne->qty : 0, 0, ',', ' ') }}</td>
                <td style="text-align:right;">{{ number_format($montant, 0, ',', ' ') }}</td>
            </tr>
        @empty
            <tr><td colspan="4" style="text-align:center;">Aucune ligne.</td></tr>
        @endforelse
    </tbody>
</table>

<p style="text-align:right;font-size:12px;margin-top:10px;">
    @if($sale->discount > 0) Remise : {{ number_format($sale->discount, 0, ',', ' ') }} FCFA<br> @endif
    @if($sale->delivery_fee > 0) Frais de livraison : {{ number_format($sale->delivery_fee, 0, ',', ' ') }} FCFA<br> @endif
    <strong>Total TTC : {{ number_format($sale->total, 0, ',', ' ') }} FCFA</strong>
</p>

<p style="font-size:11px;margin-top:14px;">
    @if($sale->mecef_status === 'transmise' && $sale->mecef_qr_ref)
        Facture normalisée MeCeF — référence : {{ $sale->mecef_qr_ref }}
    @else
        Facture émise sans certification MeCeF.
    @endif
</p>
