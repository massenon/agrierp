
@if($tab === 'bilan')
    <table class="data-table">
        <thead><tr><th>Poste</th><th style="text-align:right;">Montant (FCFA)</th></tr></thead>
        <tbody>
            <tr><td colspan="2"><strong>ACTIF — Immobilisé (Classe 2)</strong></td></tr>
            @foreach($bilan['immo'] as $ligne)
                <tr><td>{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td style="text-align:right;">{{ number_format($ligne['balance'], 0, ',', ' ') }}</td></tr>
            @endforeach
            <tr><td colspan="2"><strong>ACTIF — Circulant (Classes 3 &amp; 4)</strong></td></tr>
            @foreach(array_merge($bilan['stocks'], $bilan['creances']) as $ligne)
                <tr><td>{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td style="text-align:right;">{{ number_format($ligne['balance'], 0, ',', ' ') }}</td></tr>
            @endforeach
            <tr><td colspan="2"><strong>ACTIF — Trésorerie (Classe 5)</strong></td></tr>
            @foreach($bilan['tresorerie'] as $ligne)
                <tr><td>{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td style="text-align:right;">{{ number_format($ligne['balance'], 0, ',', ' ') }}</td></tr>
            @endforeach
            <tr><td><strong>TOTAL ACTIF</strong></td><td style="text-align:right;"><strong>{{ number_format($bilan['total_actif'], 0, ',', ' ') }}</strong></td></tr>

            <tr><td colspan="2"><strong>PASSIF — Capitaux Propres (Classe 1)</strong></td></tr>
            @foreach($bilan['capitaux'] as $ligne)
                <tr><td>{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td style="text-align:right;">{{ number_format(-$ligne['balance'], 0, ',', ' ') }}</td></tr>
            @endforeach
            <tr><td>Résultat de l'Exercice</td><td style="text-align:right;">{{ number_format($bilan['resultat'], 0, ',', ' ') }}</td></tr>
            <tr><td colspan="2"><strong>PASSIF — Dettes (Classe 4)</strong></td></tr>
            @foreach($bilan['dettes'] as $ligne)
                <tr><td>{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td style="text-align:right;">{{ number_format($ligne['balance'], 0, ',', ' ') }}</td></tr>
            @endforeach
            <tr><td><strong>TOTAL PASSIF</strong></td><td style="text-align:right;"><strong>{{ number_format($bilan['total_passif'], 0, ',', ' ') }}</strong></td></tr>
        </tbody>
    </table>
    @unless($bilan['is_balanced'])
        <p style="margin-top:12px;color:#BA1A1A;font-weight:bold;">Bilan déséquilibré — écart de {{ number_format(abs($bilan['total_actif'] - $bilan['total_passif']), 0, ',', ' ') }} FCFA.</p>
    @endunless
@endif

@if($tab === 'resultat')
    <table class="data-table">
        <thead><tr><th>Compte de Résultat — Cascade SYSCOHADA</th><th style="text-align:right;">Montant (FCFA)</th></tr></thead>
        <tbody>
            <tr><td>Ventes</td><td style="text-align:right;">{{ number_format($resultat['ventes'], 0, ',', ' ') }}</td></tr>
            <tr><td>− Achats</td><td style="text-align:right;">({{ number_format($resultat['achats'], 0, ',', ' ') }})</td></tr>
            <tr><td><strong>= MARGE COMMERCIALE</strong></td><td style="text-align:right;"><strong>{{ number_format($resultat['marge_commerciale'], 0, ',', ' ') }}</strong></td></tr>
            <tr><td>− Charges de Personnel</td><td style="text-align:right;">({{ number_format($resultat['charges_personnel'], 0, ',', ' ') }})</td></tr>
            <tr><td><strong>= EXCÉDENT BRUT D'EXPLOITATION</strong></td><td style="text-align:right;"><strong>{{ number_format($resultat['ebe'], 0, ',', ' ') }}</strong></td></tr>
            <tr><td>− Dotations aux Amortissements</td><td style="text-align:right;">({{ number_format($resultat['dotations'], 0, ',', ' ') }})</td></tr>
            <tr><td><strong>= RÉSULTAT D'EXPLOITATION</strong></td><td style="text-align:right;"><strong>{{ number_format($resultat['resultat_exploitation'], 0, ',', ' ') }}</strong></td></tr>
            <tr><td>+ Résultat Financier</td><td style="text-align:right;">{{ number_format($resultat['resultat_financier'], 0, ',', ' ') }}</td></tr>
            <tr><td><strong>= RÉSULTAT DES ACTIVITÉS ORDINAIRES (RAO)</strong></td><td style="text-align:right;"><strong>{{ number_format($resultat['rao'], 0, ',', ' ') }}</strong></td></tr>
            <tr><td>+ Résultat Hors Activités Ordinaires</td><td style="text-align:right;">({{ number_format($resultat['autres_charges'], 0, ',', ' ') }})</td></tr>
            <tr><td><strong>= RÉSULTAT NET DE L'EXERCICE</strong></td><td style="text-align:right;"><strong>{{ number_format($resultat['resultat_net'], 0, ',', ' ') }}</strong></td></tr>
        </tbody>
    </table>
@endif

@if($tab === 'tafire')
    <table class="data-table">
        <thead><tr><th>Tableau des Flux de Trésorerie (TAFIRE simplifié)</th><th style="text-align:right;">Montant (FCFA)</th></tr></thead>
        <tbody>
            <tr><td>Résultat Net de l'Exercice</td><td style="text-align:right;">{{ number_format($tafire['resultat_net'], 0, ',', ' ') }}</td></tr>
            <tr><td>+ Dotations aux Amortissements</td><td style="text-align:right;">{{ number_format($tafire['dotations'], 0, ',', ' ') }}</td></tr>
            <tr><td>− Variation du BFR</td><td style="text-align:right;">({{ number_format($tafire['variation_bfr'], 0, ',', ' ') }})</td></tr>
            <tr><td><strong>= FLUX NET D'EXPLOITATION</strong></td><td style="text-align:right;"><strong>{{ number_format($tafire['flux_exploitation'], 0, ',', ' ') }}</strong></td></tr>
            <tr><td><strong>= FLUX NET D'INVESTISSEMENT</strong></td><td style="text-align:right;"><strong>{{ number_format($tafire['flux_investissement'], 0, ',', ' ') }}</strong></td></tr>
            <tr><td><strong>= FLUX NET DE FINANCEMENT</strong></td><td style="text-align:right;"><strong>{{ number_format($tafire['flux_financement'], 0, ',', ' ') }}</strong></td></tr>
            <tr><td><strong>VARIATION DE TRÉSORERIE</strong></td><td style="text-align:right;"><strong>{{ number_format($tafire['variation_tresorerie'], 0, ',', ' ') }}</strong></td></tr>
            <tr><td>Trésorerie à l'Ouverture</td><td style="text-align:right;">{{ number_format($tafire['tresorerie_ouverture'], 0, ',', ' ') }}</td></tr>
            <tr><td><strong>TRÉSORERIE À LA CLÔTURE</strong></td><td style="text-align:right;"><strong>{{ number_format($tafire['tresorerie_cloture'], 0, ',', ' ') }}</strong></td></tr>
        </tbody>
    </table>
    @if($tafire['is_coherent'])
        <p style="margin-top:12px;font-weight:bold;">Cohérence vérifiée : Trésorerie à la Clôture = Trésorerie-Actif du Bilan.</p>
    @else
        <p style="margin-top:12px;color:#BA1A1A;font-weight:bold;">Incohérence : écart de {{ number_format($tafire['ecart'], 0, ',', ' ') }} FCFA avec la Trésorerie-Actif du Bilan ({{ number_format($tafire['tresorerie_cloture_bilan'], 0, ',', ' ') }} FCFA).</p>
    @endif
@endif

@if($tab === 'notes')
    <p><strong>Note 1 — Méthodes Comptables.</strong> Immobilisations amorties en linéaire. Stocks valorisés au Prix Moyen Pondéré (PMP). Monnaie de présentation : Franc CFA (FCFA), sans décimale.</p>

    <p><strong>Note 2 — Immobilisations.</strong> Valeur nette totale : {{ number_format($bilan['total_immo'], 0, ',', ' ') }} FCFA. Le plan comptable ne trace les immobilisations qu'au niveau des comptes de classe 2 — aucune ventilation par nature d'actif n'est présentée, faute de sous-comptes dédiés.</p>

    <p><strong>Note 3 — Stocks.</strong> Stock global valorisé au PMP : {{ number_format($stockValuation['valeur'], 0, ',', ' ') }} FCFA sur {{ $stockValuation['nb_valorises'] }} produit(s) disposant d'un historique d'achat@if($stockValuation['nb_sans_pmp'] > 0), {{ $stockValuation['nb_sans_pmp'] }} produit(s) sans PMP calculable étant exclus @endif.</p>

    <table class="data-table">
        <thead><tr><th>Note 4 — Créances et Dettes</th><th style="text-align:right;">Montant (FCFA)</th></tr></thead>
        <tbody>
            @foreach($bilan['creances'] as $ligne)
                <tr><td>Créances — {{ $ligne['label'] }} ({{ $ligne['code'] }})</td><td style="text-align:right;">{{ number_format($ligne['balance'], 0, ',', ' ') }}</td></tr>
            @endforeach
            @foreach($bilan['dettes'] as $ligne)
                <tr><td>Dettes — {{ $ligne['label'] }} ({{ $ligne['code'] }})</td><td style="text-align:right;">{{ number_format($ligne['balance'], 0, ',', ' ') }}</td></tr>
            @endforeach
        </tbody>
    </table>

    <p><strong>Note 5 — Engagements Hors Bilan.</strong> Néant à la date de clôture de la période présentée.</p>
@endif
