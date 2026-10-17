<table class="data-table">
    <thead>
        <tr>
            <th>Code Bande</th>
            <th>Espèce</th>
            <th>Stade</th>
            <th>Date Création</th>
            <th style="text-align:right;">Effectif Initial</th>
            <th style="text-align:right;">Effectif Actuel</th>
            <th style="text-align:right;">Mortalité</th>
            <th>Statut</th>
        </tr>
    </thead>
    <tbody>
        @forelse($lots as $lot)
            @php
                $mortaliteRate = $lot->initial_quantity > 0 ? round((($lot->initial_quantity - $lot->current_quantity) / $lot->initial_quantity) * 100, 1) : 0;
            @endphp
            <tr>
                <td>{{ $lot->code }}</td>
                <td>{{ $lot->species?->label }}</td>
                <td>{{ ucfirst($lot->stage) }}</td>
                <td>{{ $lot->created_date->format('d/m/Y') }}</td>
                <td style="text-align:right;">{{ $lot->initial_quantity }}</td>
                <td style="text-align:right;">{{ $lot->current_quantity }}</td>
                <td style="text-align:right;">{{ $mortaliteRate }}%</td>
                <td>{{ $lot->status === 'actif' ? 'Actif' : ucfirst($lot->status) }}</td>
            </tr>
        @empty
            <tr><td colspan="8" style="text-align:center;">Aucune bande active.</td></tr>
        @endforelse
    </tbody>
</table>
