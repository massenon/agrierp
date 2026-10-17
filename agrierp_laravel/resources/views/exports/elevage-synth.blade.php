<h3 style="margin-top:0;">Tableau 1 — Recensement</h3>
<table class="data-table">
    <thead>
        <tr>
            <th>Date</th><th>Lot</th><th style="text-align:center;">Eff. M</th><th style="text-align:center;">Eff. F</th>
            <th style="text-align:center;">Sous Mères</th><th style="text-align:center;">Sevrés</th>
            <th style="text-align:center;">Achats</th><th style="text-align:center;">Nés</th>
            <th style="text-align:center;">Morts</th><th style="text-align:center;">Eff. Final</th>
        </tr>
    </thead>
    <tbody>
        @forelse($entries as $e)
            <tr>
                <td>{{ $e->entry_date->format('d/m/Y') }}</td>
                <td>{{ $e->lot?->code }}</td>
                <td style="text-align:center;">{{ $e->effectif_m }}</td>
                <td style="text-align:center;">{{ $e->effectif_f }}</td>
                <td style="text-align:center;">{{ $e->effectif_smeres }}</td>
                <td style="text-align:center;">{{ $e->effectif_sevres }}</td>
                <td style="text-align:center;">{{ $e->achat }}</td>
                <td style="text-align:center;">{{ $e->ne }}</td>
                <td style="text-align:center;">{{ $e->mort }}</td>
                <td style="text-align:center;">{{ $e->effectif_final }}</td>
            </tr>
        @empty
            <tr><td colspan="10" style="text-align:center;">Aucune fiche sur la période.</td></tr>
        @endforelse
    </tbody>
</table>

<h3>Tableau 2 — Mouvements, Traitements &amp; Ventes</h3>
<table class="data-table">
    <thead>
        <tr>
            <th>Date</th><th>Lot</th><th>Sexe Vendu</th><th style="text-align:center;">Qté</th>
            <th style="text-align:right;">Montant</th><th>Traitement</th><th>Dose</th><th>Signes</th>
        </tr>
    </thead>
    <tbody>
        @forelse($entries as $e)
            <tr>
                <td>{{ $e->entry_date->format('d/m/Y') }}</td>
                <td>{{ $e->lot?->code }}</td>
                <td>{{ $e->vente_sexe ?? '—' }}</td>
                <td style="text-align:center;">{{ $e->vente }}</td>
                <td style="text-align:right;">{{ number_format($e->vente_montant, 0, ',', ' ') }}</td>
                <td>{{ $e->treatmentProduct?->name ?? '—' }}</td>
                <td>{{ $e->treatment_dose ?? '—' }}</td>
                <td>{{ $e->symptomes ?: 'RAS' }}</td>
            </tr>
        @empty
            <tr><td colspan="8" style="text-align:center;">Aucune fiche sur la période.</td></tr>
        @endforelse
    </tbody>
</table>

<h3>Tableau 3 — Suivi de la Ponte</h3>
<table class="data-table">
    <thead>
        <tr>
            <th>Jour</th><th>Lot</th><th style="text-align:right;">Œufs Récoltés</th>
            <th style="text-align:right;">Taux Ponte %</th><th style="text-align:right;">Cassés</th><th style="text-align:right;">Commercialisables</th>
        </tr>
    </thead>
    <tbody>
        @forelse($entries->where('ponte_total', '>', 0) as $e)
            <tr>
                <td>{{ $e->entry_date->format('d/m/Y') }}</td>
                <td>{{ $e->lot?->code }}</td>
                <td style="text-align:right;">{{ $e->ponte_total }}</td>
                <td style="text-align:right;">{{ $e->effectif_final > 0 ? number_format(($e->ponte_total / $e->effectif_final) * 100, 1) : '—' }} %</td>
                <td style="text-align:right;">{{ $e->ponte_casses }}</td>
                <td style="text-align:right;">{{ $e->ponte_total - $e->ponte_casses }}</td>
            </tr>
        @empty
            <tr><td colspan="6" style="text-align:center;">Aucune ponte sur la période.</td></tr>
        @endforelse
    </tbody>
</table>
