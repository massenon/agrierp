{{-- DEV-Q3 (DV-35) — Devis « document client » (A4 portrait) : le DEVIS d'un client, pas la liste (`exports.devis`). En-tête de la ferme, mentions et pied de page : ceux du
     gabarit commun (`exports.layout`). Le numéro `DEV-AAAA-NNN` est attribué par le serveur ; la validité est celle du devis (`validity_days`, date + jours). --}}
@php
    $ht = (int) round((float) $quote->amount);
    $ttc = (int) round((float) $quote->amount_ttc);
    $tva = $ttc - $ht;
    $fcfa = fn (int $v) => number_format($v, 0, ',', ' ').' FCFA';
@endphp
<p style="font-size:12px;">
    Devis <strong>{{ $quote->quote_number }}</strong><br>
    Client : <strong>{{ $quote->customer?->name ?? '—' }}</strong>@if($quote->customer?->phone) — {{ $quote->customer->phone }}@endif @if($quote->customer?->city) — {{ $quote->customer->city }}@endif<br>
    @if($quote->customer?->ifu) IFU du client : <strong>{{ $quote->customer->ifu }}</strong><br> @endif
    Date d'émission : <strong>{{ $quote->quote_date->format('d/m/Y') }}</strong><br>
    Valable jusqu'au : <strong>{{ $quote->valid_until->format('d/m/Y') }}</strong> (durée de validité : {{ $quote->validity_days }} jours)
</p>

<table class="data-table">
    <thead>
        <tr>
            <th>Désignation</th>
            <th style="text-align:right;">Montant HT</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td>{!! nl2br(e($quote->articles_description)) !!}</td>
            <td style="text-align:right;">{{ number_format($ht, 0, ',', ' ') }}</td>
        </tr>
    </tbody>
</table>

<p style="text-align:right;font-size:12px;margin-top:10px;">
    Montant HT : {{ $fcfa($ht) }}<br>
    TVA ({{ rtrim(rtrim(number_format((float) $quote->tva_rate, 2, ',', ' '), '0'), ',') }} %) : {{ $fcfa($tva) }}<br>
    <strong>Total TTC : {{ $fcfa($ttc) }}</strong>
</p>

@if(filled($quote->note))
    <p style="font-size:11px;">Observations : {{ $quote->note }}</p>
@endif

<table style="width:100%;border:1px solid #000;border-collapse:collapse;margin-top:28px;">
    <tr>
        <td style="padding:8px;width:50%;vertical-align:top;font-size:11px;">
            <strong>Bon pour accord</strong><br>
            Date : ____ / ____ / ________
        </td>
        <td style="padding:8px;width:50%;height:70px;vertical-align:top;font-size:11px;">
            Signature du client :
        </td>
    </tr>
</table>
