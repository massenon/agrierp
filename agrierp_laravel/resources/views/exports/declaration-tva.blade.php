<table class="data-table">
    <thead>
        <tr>
            <th colspan="7" style="text-align:left;">TVA COLLECTÉE — VENTES ASSUJETTIES</th>
        </tr>
        <tr>
            <th>N° Facture</th><th>Client</th><th>Date</th><th style="text-align:center;">Taux</th>
            <th style="text-align:right;">Montant HT</th><th style="text-align:right;">TVA</th><th style="text-align:right;">Montant TTC</th>
        </tr>
    </thead>
    <tbody>
        @forelse($declaration['collectee']['rows'] as $row)
            <tr>
                <td>{{ $row['reference'] }}</td>
                <td>{{ $row['tiers'] }}</td>
                <td>{{ \Carbon\Carbon::parse($row['date'])->format('d/m/Y') }}</td>
                <td style="text-align:center;">{{ $row['rate_label'] }}</td>
                <td style="text-align:right;">{{ number_format($row['ht'], 0, ',', ' ') }}</td>
                <td style="text-align:right;">{{ number_format($row['tva'], 0, ',', ' ') }}</td>
                <td style="text-align:right;">{{ number_format($row['ttc'], 0, ',', ' ') }}</td>
            </tr>
        @empty
            <tr><td colspan="7" style="text-align:center;">Aucune facture transmise sur cette période.</td></tr>
        @endforelse
        <tr>
            <td colspan="4"><strong>TOTAL VENTES ASSUJETTIES</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($declaration['collectee']['total_ht'], 0, ',', ' ') }}</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($declaration['collectee']['total_tva'], 0, ',', ' ') }}</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($declaration['collectee']['total_ttc'], 0, ',', ' ') }}</strong></td>
        </tr>
    </tbody>
</table>

<table class="data-table" style="margin-top:16px;">
    <thead>
        <tr>
            <th colspan="7" style="text-align:left;">TVA DÉDUCTIBLE — ACHATS ASSUJETTIS</th>
        </tr>
        <tr>
            <th>Référence</th><th>Fournisseur</th><th>Date</th><th style="text-align:center;">Taux</th>
            <th style="text-align:right;">Montant HT</th><th style="text-align:right;">TVA</th><th style="text-align:right;">Montant TTC</th>
        </tr>
    </thead>
    <tbody>
        @forelse($declaration['deductible']['rows'] as $row)
            <tr>
                <td>{{ $row['reference'] }}</td>
                <td>{{ $row['tiers'] }}</td>
                <td>{{ \Carbon\Carbon::parse($row['date'])->format('d/m/Y') }}</td>
                <td style="text-align:center;">{{ $row['rate_label'] }}</td>
                <td style="text-align:right;">{{ number_format($row['ht'], 0, ',', ' ') }}</td>
                <td style="text-align:right;">{{ number_format($row['tva'], 0, ',', ' ') }}</td>
                <td style="text-align:right;">{{ number_format($row['ttc'], 0, ',', ' ') }}</td>
            </tr>
        @empty
            <tr><td colspan="7" style="text-align:center;">Aucun achat enregistré sur cette période.</td></tr>
        @endforelse
        <tr>
            <td colspan="4"><strong>TOTAL ACHATS ASSUJETTIS</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($declaration['deductible']['total_ht'], 0, ',', ' ') }}</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($declaration['deductible']['total_tva'], 0, ',', ' ') }}</strong></td>
            <td style="text-align:right;"><strong>{{ number_format($declaration['deductible']['total_ttc'], 0, ',', ' ') }}</strong></td>
        </tr>
    </tbody>
</table>

<p style="margin-top:16px;font-weight:bold;font-size:13px;">
    {{ $declaration['is_credit'] ? 'CRÉDIT DE TVA REPORTABLE' : 'TVA NETTE À PAYER' }} :
    {{ number_format($declaration['montant_affiche'], 0, ',', ' ') }} FCFA
</p>
<p style="font-size:11px;">
    Seules les factures au statut « Transmise » (MeCeF) sont retenues dans cette déclaration.
    Taux appliqué ligne par ligne selon le champ TVA de chaque produit.
</p>
