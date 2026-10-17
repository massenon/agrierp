<table class="data-table">
    <thead>
        <tr>
            <th>N° Compte</th>
            <th>Intitulé</th>
            <th>Classe</th>
        </tr>
    </thead>
    <tbody>
        @forelse($accounts as $account)
            <tr>
                <td>{{ $account->code }}</td>
                <td>{{ $account->label }}</td>
                <td>{{ $classLabels[$account->class] ?? $account->class }}</td>
            </tr>
        @empty
            <tr><td colspan="3" style="text-align:center;">Aucun compte actif.</td></tr>
        @endforelse
    </tbody>
</table>
