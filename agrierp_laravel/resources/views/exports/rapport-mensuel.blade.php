<table class="data-table">
    <thead>
        <tr>
            <th>Indicateur</th>
            <th style="text-align:right;">{{ $moisCourant }}</th>
            <th style="text-align:right;">{{ $moisPrecedent }}</th>
            <th style="text-align:right;">Variation</th>
        </tr>
    </thead>
    <tbody>
        @foreach($indicateurs as $ligne)
            @php
                $delta = round($ligne['courant'] - $ligne['precedent'], 2);
                $decimales = $ligne['unite'] === '%' ? 1 : 0;
            @endphp
            <tr>
                <td>{{ $ligne['label'] }}</td>
                <td style="text-align:right;">{{ number_format($ligne['courant'], $decimales, ',', ' ') }} {{ $ligne['unite'] }}</td>
                <td style="text-align:right;">{{ number_format($ligne['precedent'], $decimales, ',', ' ') }} {{ $ligne['unite'] }}</td>
                <td style="text-align:right;">{{ $delta > 0 ? '+' : '' }}{{ number_format($delta, $decimales, ',', ' ') }}</td>
            </tr>
        @endforeach
    </tbody>
</table>
<p style="font-size:11px;margin-top:10px;">Rapport en lecture seule, généré depuis les données réelles de comptabilité, TVA et élevage.</p>
