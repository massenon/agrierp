<table class="data-table">
    <thead>
        <tr>
            <th>Nom</th>
            <th>Fonction</th>
            <th>Date d'embauche</th>
            <th style="text-align:right;">Salaire</th>
            <th>Statut</th>
        </tr>
    </thead>
    <tbody>
        @php
            $statusLabels = ['actif' => 'Actif', 'conge' => 'Congé', 'suspendu' => 'Suspendu'];
        @endphp
        @forelse($employees as $employee)
            <tr>
                <td>{{ $employee->last_name }} {{ $employee->first_name }}</td>
                <td>{{ $employee->position }}</td>
                <td>{{ $employee->hire_date->format('d/m/Y') }}</td>
                <td style="text-align:right;">{{ number_format($employee->base_salary, 0, ',', ' ') }} FCFA</td>
                <td>{{ $statusLabels[$employee->status] ?? $employee->status }}</td>
            </tr>
        @empty
            <tr><td colspan="5" style="text-align:center;">Aucun employé ne correspond aux filtres actifs.</td></tr>
        @endforelse
    </tbody>
</table>
