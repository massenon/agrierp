<table style="width:100%; border-collapse: collapse; font-size: 9px; margin-bottom: 12px;">
    <tr>
        <td style="width:33%; text-align:center; padding: 6px; border: 1px solid #bec9c2;"><strong>Total Recettes</strong><br>{{ number_format($kpis['recettes'], 0, ',', ' ') }} FCFA</td>
        <td style="width:33%; text-align:center; padding: 6px; border: 1px solid #bec9c2;"><strong>Total Dépenses</strong><br>{{ number_format($kpis['depenses'], 0, ',', ' ') }} FCFA</td>
        <td style="width:33%; text-align:center; padding: 6px; border: 1px solid #bec9c2;"><strong>Solde Net</strong><br>{{ number_format($kpis['solde'], 0, ',', ' ') }} FCFA</td>
    </tr>
</table>

<h3 style="color:#052e16; font-size:11px;">Recettes</h3>
<table class="data-table">
    <thead><tr><th>Date</th><th>Libellé</th><th style="text-align:right;">Montant</th></tr></thead>
    <tbody>
        @forelse($recettes as $r)
            <tr>
                <td>{{ \Carbon\Carbon::parse($r['date'])->format('d/m/Y') }}</td>
                <td>{{ $r['label'] }}</td>
                <td style="text-align:right;">+{{ number_format($r['amount'], 0, ',', ' ') }} FCFA</td>
            </tr>
        @empty
            <tr><td colspan="3" style="text-align:center;">Aucune recette sur la période.</td></tr>
        @endforelse
    </tbody>
</table>

<h3 style="color:#052e16; font-size:11px; margin-top:12px;">Dépenses</h3>
<table class="data-table">
    <thead><tr><th>Date</th><th>Libellé</th><th style="text-align:right;">Montant</th></tr></thead>
    <tbody>
        @forelse($depenses as $d)
            <tr>
                <td>{{ \Carbon\Carbon::parse($d['date'])->format('d/m/Y') }}</td>
                <td>{{ $d['label'] }}</td>
                <td style="text-align:right;">-{{ number_format($d['amount'], 0, ',', ' ') }} FCFA</td>
            </tr>
        @empty
            <tr><td colspan="3" style="text-align:center;">Aucune dépense sur la période.</td></tr>
        @endforelse
    </tbody>
</table>
