<table class="data-table">
    <thead>
        <tr>
            <th>Nom</th>
            <th>Email</th>
            <th>Rôle</th>
            <th>Statut</th>
        </tr>
    </thead>
    <tbody>
        @forelse($users as $user)
            <tr>
                <td>{{ $user->name }}</td>
                <td>{{ $user->email }}</td>
                <td>{{ ucfirst($user->roles->first()?->name ?? '—') }}</td>
                <td>{{ $user->is_active ? 'Actif' : 'Désactivé' }}</td>
            </tr>
        @empty
            <tr><td colspan="4" style="text-align:center;">Aucun utilisateur ne correspond aux filtres actifs.</td></tr>
        @endforelse
    </tbody>
</table>
