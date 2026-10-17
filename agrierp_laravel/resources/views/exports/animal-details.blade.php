<p style="font-size:13px;font-weight:bold;">Sujet {{ $animal->identifier }} — {{ $animal->species?->label ?? '—' }}
    @if($animal->breed) ({{ $animal->breed }}) @endif
    · {{ $animal->sex === 'F' ? 'Femelle' : 'Mâle' }} · {{ ucfirst($animal->status) }}</p>

<table class="data-table">
    <thead><tr><th colspan="2" style="text-align:left;">IDENTIFICATION</th></tr></thead>
    <tbody>
        <tr><td>Catégorie</td><td>{{ ucfirst($animal->category) }}</td></tr>
        <tr><td>Date de naissance</td><td>{{ $animal->birth_date?->format('d/m/Y') ?: '—' }}</td></tr>
        <tr><td>Date d'entrée</td><td>{{ $animal->entry_date->format('d/m/Y') }}</td></tr>
        <tr><td>Origine</td><td>{{ $animal->origin ?: '—' }}</td></tr>
        <tr><td>Bande</td><td>{{ $animal->lot?->code ?: '—' }}</td></tr>
        <tr><td>Cage</td><td>{{ $animal->cage ?: '—' }}</td></tr>
    </tbody>
</table>

<table class="data-table" style="margin-top:16px;">
    <thead>
        <tr><th colspan="5" style="text-align:left;">REPRODUCTION</th></tr>
        <tr><th>Saillie</th><th>Rôle</th><th>Mise bas</th><th style="text-align:right;">Nés vivants</th><th style="text-align:right;">Nés morts</th></tr>
    </thead>
    <tbody>
        @forelse($reproduction as $event)
            <tr>
                <td>{{ $event->saillie_date->format('d/m/Y') }}</td>
                <td>{{ $event->mother_ref === $animal->identifier ? 'Mère' : 'Géniteur' }}</td>
                <td>{{ $event->mise_bas_date_actual?->format('d/m/Y') ?: '—' }}</td>
                <td style="text-align:right;">{{ $event->nes_vivants ?? '—' }}</td>
                <td style="text-align:right;">{{ $event->nes_morts ?? '—' }}</td>
            </tr>
        @empty
            <tr><td colspan="5" style="text-align:center;">Aucun événement de reproduction.</td></tr>
        @endforelse
    </tbody>
</table>

<table class="data-table" style="margin-top:16px;">
    <thead>
        <tr><th colspan="4" style="text-align:left;">SOINS DE LA BANDE (prophylaxie administrée par bande, non individuelle)</th></tr>
        <tr><th>Date</th><th>Action</th><th>Produit</th><th>Dose</th></tr>
    </thead>
    <tbody>
        @forelse($soins as $soin)
            <tr>
                <td>{{ $soin->record_date->format('d/m/Y') }}</td>
                <td>{{ $soin->action_type }}</td>
                <td>{{ $soin->product_used ?: '—' }}</td>
                <td>{{ $soin->dose ?: '—' }}</td>
            </tr>
        @empty
            <tr><td colspan="4" style="text-align:center;">Aucun soin enregistré.</td></tr>
        @endforelse
    </tbody>
</table>

<table class="data-table" style="margin-top:16px;">
    <thead>
        <tr><th colspan="3" style="text-align:left;">MOUVEMENTS</th></tr>
        <tr><th>Date</th><th>Mouvement</th><th>Détail</th></tr>
    </thead>
    <tbody>
        @foreach($mouvements as $m)
            <tr>
                <td>{{ \Carbon\Carbon::parse($m['date'])->format('d/m/Y') }}</td>
                <td>{{ $m['libelle'] }}</td>
                <td>{{ $m['detail'] }}</td>
            </tr>
        @endforeach
    </tbody>
</table>

<p style="font-size:11px;margin-top:12px;">
    Alimentation, production et documents ne figurent pas dans cette fiche : aucune source par sujet
    n'existe pour ces informations (rationnement et ponte sont suivis par bande).
</p>
