<table class="data-table">
    <thead>
        <tr>
            <th>Employé</th>
            <th>Date</th>
            <th>Arrivée</th>
            <th>Départ</th>
            <th>Statut</th>
        </tr>
    </thead>
    <tbody>
        @php
            $statusLabels = ['present' => 'Présent', 'absent' => 'Absent', 'retard' => 'Retard', 'conge' => 'Congé'];
        @endphp
        @forelse($records as $record)
            <tr>
                <td>{{ $record->employee?->last_name }} {{ $record->employee?->first_name }}</td>
                <td>{{ $record->attendance_date->format('d/m/Y') }}</td>
                <td>{{ $record->check_in ?? '—' }}</td>
                <td>{{ $record->check_out ?? '—' }}</td>
                <td>{{ $statusLabels[$record->status] ?? $record->status }}</td>
            </tr>
        @empty
            <tr><td colspan="5" style="text-align:center;">Aucun pointage ne correspond aux filtres actifs.</td></tr>
        @endforelse
    </tbody>
</table>
