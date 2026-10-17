<table class="data-table">
    <thead>
        <tr>
            <th>Rôle</th>
            @foreach($modules as $module)
                <th style="text-align:center;">{{ $module }}</th>
            @endforeach
            <th style="text-align:right;">Utilisateurs</th>
        </tr>
    </thead>
    <tbody>
        @forelse($rows as $row)
            <tr>
                <td>{{ ucfirst($row['role']->name) }}</td>
                @foreach($modules as $module)
                    <td style="text-align:center;">{{ $row['modules'][$module] ? 'Oui' : '—' }}</td>
                @endforeach
                <td style="text-align:right;">{{ $row['users_count'] }}</td>
            </tr>
        @empty
            <tr><td colspan="{{ count($modules) + 2 }}" style="text-align:center;">Aucun rôle configuré.</td></tr>
        @endforelse
    </tbody>
</table>
