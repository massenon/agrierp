@php
    // Ticket EX8 (EF11) — les deux colonnes « Exercice N » / « Exercice N-1 » au PDF, comme à l'écran (« — » sans N-1).
    $m = fn ($v) => \App\Support\ComparatifNMoinsUn::montant($v);
    $p = fn ($v) => $v === null ? '—' : '('.\App\Support\ComparatifNMoinsUn::montant($v).')';
    $neg = fn ($v) => $v === null ? null : -$v;
    $c = $bilanComparatif;
    $b1 = $c['n1'];
    $cr = $resultatComparatif;
    $r1 = $cr['n1'];
    $enteteN = \App\Support\ComparatifNMoinsUn::ENTETE_N.' ('.\App\Support\ComparatifNMoinsUn::sousTitre($c['exercice_n']).')';
    $cascade = [
        ['Ventes', 'ventes', false, false],
        ['− Achats', 'achats', true, false],
        ['= MARGE COMMERCIALE', 'marge_commerciale', false, true],
        ['− Charges de Personnel', 'charges_personnel', true, false],
        ["= EXCÉDENT BRUT D'EXPLOITATION", 'ebe', false, true],
        ['− Dotations aux Amortissements', 'dotations', true, false],
        ["= RÉSULTAT D'EXPLOITATION", 'resultat_exploitation', false, true],
        ['+ Résultat Financier', 'resultat_financier', false, false],
        ['= RÉSULTAT DES ACTIVITÉS ORDINAIRES (RAO)', 'rao', false, true],
        ['+ Résultat Hors Activités Ordinaires', 'autres_charges', true, false],
        ["= RÉSULTAT NET DE L'EXERCICE", 'resultat_net', false, true],
    ];
    $enteteN1 = \App\Support\ComparatifNMoinsUn::ENTETE_N1.' ('.\App\Support\ComparatifNMoinsUn::sousTitre($c['exercice_n1']).')';
@endphp

@if($tab === 'bilan')
    <table class="data-table">
        <thead><tr><th>Poste</th><th style="text-align:right;">{{ $enteteN }}</th><th style="text-align:right;">{{ $enteteN1 }}</th></tr></thead>
        <tbody>
            <tr><td colspan="3"><strong>ACTIF — Immobilisé (Classe 2)</strong></td></tr>
            @foreach($c['lignes']['immo'] as $ligne)
                <tr><td>{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td style="text-align:right;" data-colonne="n">{{ $m($ligne['n']) }}</td><td style="text-align:right;" data-colonne="n1">{{ $m($ligne['n1']) }}</td></tr>
            @endforeach
            <tr><td colspan="3"><strong>ACTIF — Circulant (Classes 3 &amp; 4)</strong></td></tr>
            @foreach(array_merge($c['lignes']['stocks'], $c['lignes']['creances']) as $ligne)
                <tr><td>{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td style="text-align:right;" data-colonne="n">{{ $m($ligne['n']) }}</td><td style="text-align:right;" data-colonne="n1">{{ $m($ligne['n1']) }}</td></tr>
            @endforeach
            <tr><td colspan="3"><strong>ACTIF — Trésorerie (Classe 5)</strong></td></tr>
            @foreach($c['lignes']['tresorerie'] as $ligne)
                <tr><td>{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td style="text-align:right;" data-colonne="n">{{ $m($ligne['n']) }}</td><td style="text-align:right;" data-colonne="n1">{{ $m($ligne['n1']) }}</td></tr>
            @endforeach
            <tr><td><strong>TOTAL ACTIF</strong></td><td style="text-align:right;" data-colonne="n"><strong>{{ $m($c['n']['total_actif']) }}</strong></td><td style="text-align:right;" data-colonne="n1"><strong>{{ $m($b1['total_actif'] ?? null) }}</strong></td></tr>

            <tr><td colspan="3"><strong>PASSIF — Capitaux Propres (Classe 1)</strong></td></tr>
            @foreach($c['lignes']['capitaux'] as $ligne)
                <tr><td>{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td style="text-align:right;" data-colonne="n">{{ $m(-$ligne['n']) }}</td><td style="text-align:right;" data-colonne="n1">{{ $m($neg($ligne['n1'])) }}</td></tr>
            @endforeach
            <tr><td>Résultat de l'Exercice</td><td style="text-align:right;" data-colonne="n">{{ $m($c['n']['resultat']) }}</td><td style="text-align:right;" data-colonne="n1">{{ $m($b1['resultat'] ?? null) }}</td></tr>
            <tr><td colspan="3"><strong>PASSIF — Dettes (Classe 4)</strong></td></tr>
            @foreach($c['lignes']['dettes'] as $ligne)
                <tr><td>{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td style="text-align:right;" data-colonne="n">{{ $m($ligne['n']) }}</td><td style="text-align:right;" data-colonne="n1">{{ $m($ligne['n1']) }}</td></tr>
            @endforeach
            <tr><td><strong>TOTAL PASSIF</strong></td><td style="text-align:right;" data-colonne="n"><strong>{{ $m($c['n']['total_passif']) }}</strong></td><td style="text-align:right;" data-colonne="n1"><strong>{{ $m($b1['total_passif'] ?? null) }}</strong></td></tr>
        </tbody>
    </table>
    @unless($bilan['is_balanced'])
        <p style="margin-top:12px;color:#BA1A1A;font-weight:bold;">Bilan déséquilibré — écart de {{ number_format(abs($bilan['total_actif'] - $bilan['total_passif']), 0, ',', ' ') }} FCFA.</p>
    @endunless
@endif

@if($tab === 'resultat')
    <table class="data-table">
        <thead><tr><th>Compte de Résultat — Cascade SYSCOHADA</th><th style="text-align:right;">{{ $enteteN }}</th><th style="text-align:right;">{{ $enteteN1 }}</th></tr></thead>
        <tbody>
            @foreach($cascade as [$libelle, $cle, $entreParentheses, $gras])
                @php
                    $vn = $entreParentheses ? $p($cr['n'][$cle]) : $m($cr['n'][$cle]);
                    $v1 = $entreParentheses ? $p($r1[$cle] ?? null) : $m($r1[$cle] ?? null);
                @endphp
                @if($gras)
                    <tr><td><strong>{{ $libelle }}</strong></td><td style="text-align:right;" data-colonne="n"><strong>{{ $vn }}</strong></td><td style="text-align:right;" data-colonne="n1"><strong>{{ $v1 }}</strong></td></tr>
                @else
                    <tr><td>{{ $libelle }}</td><td style="text-align:right;" data-colonne="n">{{ $vn }}</td><td style="text-align:right;" data-colonne="n1">{{ $v1 }}</td></tr>
                @endif
            @endforeach
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

{{-- 🔴→✅ Ticket EX8 — « d'achat@if(...) » collé à un mot n'était pas compilé en directive : son « @endif » restait seul et
     la vue entière ne compilait pas — « Exporter PDF (Onglet Actif) » finissait en erreur 500 sur LES QUATRE onglets. --}}
@if($tab === 'notes')
    <p><strong>Note 1 — Méthodes Comptables.</strong> Immobilisations amorties en linéaire. Stocks valorisés au Prix Moyen Pondéré (PMP). Monnaie de présentation : Franc CFA (FCFA), sans décimale.</p>

    <p><strong>Note 2 — Immobilisations.</strong> Valeur nette totale : {{ number_format($bilan['total_immo'], 0, ',', ' ') }} FCFA. Le plan comptable ne trace les immobilisations qu'au niveau des comptes de classe 2 — aucune ventilation par nature d'actif n'est présentée, faute de sous-comptes dédiés.</p>

    <p><strong>Note 3 — Stocks.</strong> Stock global valorisé au PMP : {{ number_format($stockValuation['valeur'], 0, ',', ' ') }} FCFA sur {{ $stockValuation['nb_valorises'] }} produit(s) disposant d'un historique d'achat{{ $stockValuation['nb_sans_pmp'] > 0 ? ', '.$stockValuation['nb_sans_pmp'].' produit(s) sans PMP calculable étant exclus' : '' }}.</p>

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
