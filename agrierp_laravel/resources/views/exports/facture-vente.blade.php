{{-- Facture d'une vente (Facturation) — avec ou sans certification MeCeF. --}}
@php $normalisee = $sale->estADeclarer(); @endphp
<p style="font-size:12px;">
    Facture <strong>{{ $sale->numero_facture }}</strong> du <strong>{{ $sale->date_effective->format('d/m/Y') }}</strong><br>
    @if($normalisee)
        {{-- Facture normalisée : l'identité fiscale de l'ACHETEUR saisie à la vente (nom, IFU facultatif, AIB). --}}
        Client : <strong>{{ $sale->client_nom_facture ?: ($sale->customer?->name ?? 'Client Anonyme') }}</strong><br>
        @if($sale->client_ifu) IFU du client : <strong>{{ $sale->client_ifu }}</strong><br> @endif
        @if($sale->aib_taux)
            AIB : <strong>{{ \App\Support\AibTaux::LIBELLES[$sale->aib_taux] ?? $sale->aib_taux }}</strong>
            @if($sale->mecef_aib_montant !== null && (float) $sale->mecef_aib_montant > 0) — montant calculé par la DGI : {{ number_format((float) $sale->mecef_aib_montant, 0, ',', ' ') }} FCFA @endif
            <br>
        @endif
    @else
        Client : <strong>{{ $sale->customer?->name ?? 'Client Anonyme' }}</strong>
        @if($sale->customer?->phone) — {{ $sale->customer->phone }} @endif
        <br>
    @endif
    Mode de règlement : {{ \App\Support\ModePaiement::libelle($sale->payment_mode) }}
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
        {{-- Frais de livraison INCLUS dans la vente (nouvelles ventes) : une ligne, comprise dans le total. --}}
        @if($sale->delivery_in_total && (float) $sale->delivery_fee > 0)
            <tr>
                <td>Frais de livraison</td>
                <td style="text-align:right;">1</td>
                <td style="text-align:right;">{{ number_format($sale->delivery_fee, 0, ',', ' ') }}</td>
                <td style="text-align:right;">{{ number_format($sale->delivery_fee, 0, ',', ' ') }}</td>
            </tr>
        @endif
    </tbody>
</table>

<p style="text-align:right;font-size:12px;margin-top:10px;">
    @if($sale->discount > 0) Remise : {{ number_format($sale->discount, 0, ',', ' ') }} FCFA<br> @endif
    @if($sale->delivery_fee > 0 && ! $sale->delivery_in_total) Frais de livraison : {{ number_format($sale->delivery_fee, 0, ',', ' ') }} FCFA<br> @endif
    <strong>Total TTC : {{ number_format($sale->total, 0, ',', ' ') }} FCFA</strong>
</p>

{{-- MECEF-1 — les mentions de la facture NORMALISÉE viennent de la DGI ; sans normalisation, aucune mention inventée. --}}
@if($sale->estNormalisee() && $sale->mecef_qr_ref)
    @php
        $qrSvg = (string) \SimpleSoftwareIO\QrCode\Facades\QrCode::size(110)->margin(0)->generate($sale->mecef_qr_ref);
    @endphp
    <table style="width:100%;margin-top:14px;font-size:11px;" id="mentions-mecef">
        <tr>
            <td style="vertical-align:top;">
                <strong>Facture normalisée MeCeF</strong>@unless($sale->mecef_code) — référence : {{ $sale->mecef_qr_ref }}@endunless<br>
                @if($sale->mecef_code) Code MeCeF/DGI : {{ $sale->mecef_code }}<br> @endif
                @if($sale->mecef_nim) NIM : {{ $sale->mecef_nim }}<br> @endif
                @if($sale->mecef_compteurs) Compteurs : {{ $sale->mecef_compteurs }}<br> @endif
                @if($sale->mecef_normalise_le) Normalisée le {{ $sale->mecef_normalise_le->format('d/m/Y à H:i:s') }}<br> @endif
            </td>
            <td style="width:120px;text-align:right;vertical-align:top;">
                <img src="data:image/svg+xml;base64,{{ base64_encode($qrSvg) }}" width="110" height="110" alt="QR code DGI">
            </td>
        </tr>
    </table>
@elseif($normalisee)
    {{-- Facture normalisée demandée, pas encore certifiée : aucun QR ni code inventé. --}}
    <p style="font-size:11px;margin-top:14px;" id="mention-en-attente">{{ \App\Support\FactureType::MENTION_EN_ATTENTE }}</p>
@else
    <p style="font-size:11px;margin-top:14px;" id="mention-simple">{{ \App\Support\FactureType::MENTION_SIMPLE }}</p>
@endif
