<table class="data-table">
    <thead>
        <tr>
            <th>Employé</th>
            <th>Poste</th>
            <th style="text-align:right;">Salaire Brut</th>
            <th style="text-align:right;">Absences</th>
            <th style="text-align:right;">Ret. Absences</th>
            <th style="text-align:right;">Ret. CNSS</th>
            <th style="text-align:right;">Net à Payer</th>
            <th>Statut</th>
        </tr>
    </thead>
    <tbody>
        @forelse($rows as $row)
            <tr>
                <td>{{ $row['employee']->last_name }} {{ $row['employee']->first_name }}</td>
                <td>{{ $row['employee']->position }}</td>
                <td style="text-align:right;">{{ number_format($row['gross'], 0, ',', ' ') }} FCFA</td>
                <td style="text-align:right;">{{ $row['absence_days'] ?? '—' }}</td>
                <td style="text-align:right;">{{ number_format($row['absence_deduction'], 0, ',', ' ') }} FCFA</td>
                <td style="text-align:right;">{{ number_format($row['cnss_deduction'], 0, ',', ' ') }} FCFA</td>
                <td style="text-align:right;">{{ number_format($row['net'], 0, ',', ' ') }} FCFA</td>
                <td>{{ $row['paid'] ? 'Réglé' : 'En attente' }}</td>
            </tr>
        @empty
            <tr><td colspan="8" style="text-align:center;">Aucun employé actif.</td></tr>
        @endforelse
    </tbody>
</table>
