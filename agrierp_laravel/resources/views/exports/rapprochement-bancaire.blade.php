<p style="font-size:12px;">
    Solde Livre : <strong>{{ number_format($reconciliation['solde_livre'], 0, ',', ' ') }} FCFA</strong> —
    Solde Relevé : <strong>{{ number_format($reconciliation['solde_releve'], 0, ',', ' ') }} FCFA</strong> —
    Opérations en instance : <strong>{{ number_format(abs($reconciliation['en_instance']), 0, ',', ' ') }} FCFA</strong>
</p>

<table class="data-table">
    <thead>
        <tr><th colspan="4" style="text-align:left;">GRAND LIVRE{{ $account ? ' — Compte '.$account->code.' '.$account->label : '' }}</th></tr>
        <tr><th>Date</th><th>Libellé</th><th style="text-align:right;">Montant</th><th style="text-align:center;">Statut</th></tr>
    </thead>
    <tbody>
        @forelse($reconciliation['ledger'] as $ligne)
            <tr>
                <td>{{ \Carbon\Carbon::parse($ligne['date'])->format('d/m/Y') }}</td>
                <td>{{ $ligne['label'] }}</td>
                <td style="text-align:right;">{{ number_format($ligne['amount'], 0, ',', ' ') }}</td>
                <td style="text-align:center;">{{ $ligne['is_matched'] ? 'Pointé' : 'En instance' }}</td>
            </tr>
        @empty
            <tr><td colspan="4" style="text-align:center;">Aucune écriture sur la période.</td></tr>
        @endforelse
    </tbody>
</table>

<table class="data-table" style="margin-top:16px;">
    <thead>
        <tr><th colspan="4" style="text-align:left;">RELEVÉ BANCAIRE IMPORTÉ</th></tr>
        <tr><th>Date</th><th>Libellé</th><th style="text-align:right;">Montant</th><th style="text-align:center;">Statut</th></tr>
    </thead>
    <tbody>
        @forelse($reconciliation['statement'] as $ligne)
            <tr>
                <td>{{ \Carbon\Carbon::parse($ligne['date'])->format('d/m/Y') }}</td>
                <td>{{ $ligne['label'] }}</td>
                <td style="text-align:right;">{{ number_format($ligne['amount'], 0, ',', ' ') }}</td>
                <td style="text-align:center;">{{ $ligne['is_matched'] ? 'Pointé' : 'Nouveau — à saisir' }}</td>
            </tr>
        @empty
            <tr><td colspan="4" style="text-align:center;">Aucun relevé importé sur la période.</td></tr>
        @endforelse
    </tbody>
</table>

<p style="margin-top:12px;font-weight:bold;{{ $reconciliation['is_balanced'] ? '' : 'color:#BA1A1A;' }}">
    {{ $reconciliation['is_balanced']
        ? 'Rapprochement équilibré — écart nul.'
        : 'Rapprochement déséquilibré — écart de '.number_format($reconciliation['ecart'], 0, ',', ' ').' FCFA à justifier avant clôture.' }}
</p>
