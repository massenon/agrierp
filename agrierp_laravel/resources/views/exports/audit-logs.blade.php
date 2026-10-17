<table class="data-table">
    <thead>
        <tr>
            <th>Horodatage</th>
            <th>Utilisateur</th>
            <th>Action</th>
            <th>Module</th>
        </tr>
    </thead>
    <tbody>
        @forelse($logs as $log)
            <tr>
                <td>{{ $log->created_at->format('d/m/Y H:i') }}</td>
                <td>{{ $log->user?->name ?? 'Inconnu' }}</td>
                <td>{{ $log->action_label }}</td>
                <td>{{ $log->module_label ?? '—' }}</td>
            </tr>
        @empty
            <tr><td colspan="4" style="text-align:center;">Aucun événement pour cette période.</td></tr>
        @endforelse
    </tbody>
</table>
