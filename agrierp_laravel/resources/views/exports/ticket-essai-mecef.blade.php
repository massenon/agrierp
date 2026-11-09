{{-- CONF-2 — TICKET D'ESSAI d'une machine MeCeF, 80 mm de large : la charge utile du boîtier (`ChargeBoitierEltrade`) rendue en
     ticket de caisse. Document de DÉMONSTRATION (dossier `presentation/`) : jamais une facture, jamais transmis à la DGI. --}}
@php
    $tva = app(\App\Services\VatDeclarationService::class);
    $fcfa = fn ($n) => number_format((float) $n, 0, ',', ' ');
    $qte = fn ($q) => rtrim(rtrim(number_format((float) $q, 3, ',', ''), '0'), ',');
    $groupes = [];
    foreach ($charge['products'] as $p) {
        $groupes[$p['tax']] = ($groupes[$p['tax']] ?? 0) + (int) round($p['price'] * $p['items']);
    }
    ksort($groupes);
    $total = array_sum($groupes);
    $ttcB = $groupes['B'] ?? 0;
    $tvaB = $tva->tva((float) $ttcB, 0.18);
    $modes = ['E' => 'Espèces', 'M' => 'Mobile money', 'V' => 'Virement', 'C' => 'Carte bancaire', 'D' => 'Chèque', 'A' => 'Autre'];
@endphp
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <title>Ticket d'essai MeCeF — SPÉCIMEN</title>
    <style>
        @page { margin: 8pt 9pt 8pt 9pt; }
        body { font-family: 'DejaVu Sans', sans-serif; font-size: 7.4pt; color: #000; }
        .c { text-align: center; }
        .r { text-align: right; }
        .g { font-weight: bold; }
        .titre { font-size: 9.5pt; font-weight: bold; }
        .specimen { border: 1.4pt solid #000; text-align: center; font-weight: bold; font-size: 8.5pt; padding: 3pt 2pt; margin: 4pt 0; }
        .trait { border-top: 0.8pt dashed #000; margin: 4pt 0; height: 0; }
        table { width: 100%; border-collapse: collapse; }
        td { vertical-align: top; padding: 1pt 0; }
        .petit { font-size: 6.4pt; }
        .total td { font-size: 10pt; font-weight: bold; padding-top: 3pt; }
    </style>
</head>
<body>
    <div class="c titre">FERME ÉCOLE OLOUWACHEGOUN</div>
    <div class="c petit">Attan-Ewé, Ikpinlè, Adja-Ouèrè (Bénin)</div>
    <div class="c petit">IFU : {{ $ifu }} (FICTIF)</div>

    <div class="specimen">SPÉCIMEN — ESSAI MeCeF<br><span style="font-size:6.6pt;">Pas une facture · rien transmis à la DGI</span></div>

    <table class="petit">
        <tr><td>Date : {{ $date->format('d/m/Y H:i') }}</td><td class="r">Vendeur : {{ $charge['seller_name'] }}</td></tr>
        <tr><td colspan="2">Type : {{ $charge['vt'] ?? $charge['rt'] }} — Facture de vente</td></tr>
        @isset($charge['buyer_name'])<tr><td colspan="2">Client : {{ $charge['buyer_name'] }}</td></tr>@endisset
        @isset($charge['buyer_ifu'])<tr><td colspan="2">IFU client : {{ $charge['buyer_ifu'] }}</td></tr>@endisset
    </table>

    <div class="trait"></div>
    <table>
        @foreach($charge['products'] as $p)
            <tr><td colspan="3" class="g">{{ $p['label'] }}</td></tr>
            <tr class="petit">
                <td style="width:56%;">{{ $qte($p['items']) }} × {{ $fcfa($p['price']) }}@isset($p['original_price']) <span class="petit">(avant remise {{ $fcfa($p['original_price']) }})</span>@endisset</td>
                <td class="r" style="width:30%;">{{ $fcfa($p['price'] * $p['items']) }}</td>
                <td class="r g" style="width:14%;">{{ $p['tax'] }}</td>
            </tr>
        @endforeach
    </table>
    <div class="trait"></div>

    <table class="total"><tr><td>TOTAL TTC</td><td class="r">{{ $fcfa($total) }} FCFA</td></tr></table>
    <table class="petit">
        @isset($groupes['B'])
            <tr><td>Groupe B (taxable 18 %) — TTC</td><td class="r">{{ $fcfa($ttcB) }}</td></tr>
            <tr><td>&nbsp;&nbsp;dont HT</td><td class="r">{{ $fcfa($ttcB - $tvaB) }}</td></tr>
            <tr><td>&nbsp;&nbsp;dont TVA 18 %</td><td class="r">{{ $fcfa($tvaB) }}</td></tr>
        @endisset
        @isset($groupes['A'])
            <tr><td>Groupe A (exonéré) — TTC</td><td class="r">{{ $fcfa($groupes['A']) }}</td></tr>
        @endisset
        <tr><td>AIB</td><td class="r">{{ $charge['aib'] }}</td></tr>
    </table>
    <div class="trait"></div>

    <table>
        @foreach($charge['payments'] as $p)
            <tr><td class="g">Paiement : {{ $modes[$p['mode']] ?? $p['mode'] }}</td><td class="r g">{{ $fcfa($p['amount']) }}</td></tr>
        @endforeach
    </table>
    <div class="trait"></div>

    {{-- Mentions que la machine IMPRIME elle-même : ici FICTIVES et marquées comme telles. --}}
    <div class="c petit g">MENTIONS DE LA MACHINE (FICTIVES)</div>
    <div class="c petit">NIM : {{ $vente->mecef_nim }}<br>Code MeCeF/DGI : {{ $vente->mecef_code }}<br>Compteurs : {{ $vente->mecef_compteurs }}</div>
    @php $qrSvg = (string) \SimpleSoftwareIO\QrCode\Facades\QrCode::size(120)->margin(0)->generate($vente->mecef_qr_ref); @endphp
    <div class="c" style="margin-top:4pt;"><img src="data:image/svg+xml;base64,{{ base64_encode($qrSvg) }}" width="104" height="104" alt="QR fictif"></div>
    <div class="c petit" style="margin-top:2pt;">QR FICTIF — ne pas scanner</div>
    <div class="trait"></div>
    <div class="c petit">Merci de votre confiance — LogiAgriERP</div>
    <div class="specimen" style="margin-top:5pt;">SPÉCIMEN</div>
</body>
</html>
