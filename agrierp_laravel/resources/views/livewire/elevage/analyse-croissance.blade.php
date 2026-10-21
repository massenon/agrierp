<div>
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm mb-md">
        <div>
            <h2 class="text-lg lg:text-xl font-bold flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald">monitoring</span>Analyse des Croissances — GMQ</h2>
            <p class="text-xs text-outline mt-xs">Gain Moyen Quotidien = (Poids actuel − Poids précédent) ÷ Jours écoulés. Calculé automatiquement à partir des pesées enregistrées dans les fiches journalières.</p>
        </div>
        <div class="flex items-center gap-xs">
            <select wire:model.live="especeFilter" class="h-11 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold">
                <option value="">Toutes les Espèces</option>
                @foreach($this->species as $espece)
                    <option value="{{ $espece->code }}">{{ $espece->label }}</option>
                @endforeach
            </select>
            <button type="button" wire:click="exportAnalyseCroissancePdf" wire:loading.attr="disabled" wire:target="exportAnalyseCroissancePdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
            </button>
        </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md mb-lg">
        @forelse($this->averages as $moyenne)
            <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-emerald shadow-sm">
                <span class="text-[10px] text-outline font-bold uppercase">GMQ Moyen {{ $moyenne['label'] }}</span>
                <span class="text-xl font-extrabold block mt-xs">{{ $moyenne['gmq'] }} g/j</span>
                @if($moyenne['objectif_min'] !== null)
                    @php
                        $dansCible = $moyenne['gmq'] >= $moyenne['objectif_min'] && $moyenne['gmq'] <= $moyenne['objectif_max'];
                    @endphp
                    <span class="text-[10px] font-bold {{ $dansCible ? 'text-brand-emerald' : 'text-error-deep' }}">
                        Objectif : {{ $moyenne['objectif_min'] }}-{{ $moyenne['objectif_max'] }} g/j
                        {{ $dansCible ? '✓' : '— hors cible ⚠' }}
                    </span>
                @else
                    <span class="text-[10px] text-outline font-bold">Objectif non défini pour cette espèce</span>
                @endif
            </div>
        @empty
            <div class="bg-white p-md rounded-lg border border-outline-variant col-span-2 lg:col-span-3">
                <p class="text-xs text-outline">Aucun lot ne dispose encore de deux pesées : le GMQ ne peut pas être calculé. Saisissez les pesées dans les fiches journalières.</p>
            </div>
        @endforelse
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-info-blue shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase">Lots Suivis (Pesées &ge; 2)</span>
            <span class="text-xl font-extrabold block mt-xs">{{ $this->trackedCount }}</span>
        </div>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable text-xs">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">Bande</th>
                        <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">Espèce</th>
                        <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">Dernière Pesée</th>
                        <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase">Poids Précédent (g)</th>
                        <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase">Poids Actuel (g)</th>
                        <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase">Jours Écoulés</th>
                        <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase">GMQ (g/jour)</th>
                        <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">Statut vs Objectif</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->rows as $i => $row)
                        <tr class="rrow border-b border-outline-variant {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                            <td data-label="Bande" class="px-sm py-sm font-bold text-brand-forest">{{ $row['lot_code'] }}</td>
                            <td data-label="Espèce" class="px-sm py-sm">{{ $row['species_label'] }}</td>
                            <td data-label="Dernière Pesée" class="px-sm py-sm">{{ \Carbon\Carbon::parse($row['date_pesee'])->format('d/m/Y') }}</td>
                            <td data-label="Poids Précédent" class="px-sm py-sm text-right">{{ number_format($row['poids_precedent'], 0, ',', ' ') }}</td>
                            <td data-label="Poids Actuel" class="px-sm py-sm text-right font-bold">{{ number_format($row['poids_actuel'], 0, ',', ' ') }}</td>
                            <td data-label="Jours" class="px-sm py-sm text-right">{{ $row['jours'] }}</td>
                            <td data-label="GMQ" class="px-sm py-sm text-right font-mono font-extrabold text-brand-emerald">{{ $row['gmq'] }}</td>
                            <td data-label="Statut" class="px-sm py-sm">
                                @switch($row['statut'])
                                    @case('sous_objectif')
                                        <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[10px] font-bold border bg-error-bg text-error-deep border-error-red/30">Sous objectif</span>
                                        @break
                                    @case('au_dessus')
                                        <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[10px] font-bold border bg-info-blue/10 text-info-blue border-info-blue/30">Au-dessus objectif</span>
                                        @break
                                    @case('dans_cible')
                                        <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[10px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Dans la cible</span>
                                        @break
                                    @default
                                        <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[10px] font-bold border bg-surface-zebra text-outline border-outline-variant" title="Aucun barème pour {{ $row['species_label'] }} au stade {{ $row['stage'] }}">Objectif non défini</span>
                                @endswitch
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="8" class="px-md py-lg text-center text-outline">Aucun lot avec au moins deux pesées pour ce filtre.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <div class="mt-md bg-info-blue/10 border border-info-blue/20 rounded-lg p-md text-xs text-brand-forest">
        <span class="material-symbols-outlined text-[16px] align-middle mr-xs">info</span>
        Les données de pesée proviennent des onglets « Pesée » des Fiches Journalières (Lapins, Volailles, Porcs). Chaque nouvelle pesée enrichit automatiquement cette analyse. Le GMQ affiché ici compare les <strong>deux dernières pesées</strong> ; le tableau de bord Élevage affiche, lui, le GMQ cumulé depuis la première pesée du lot.
    </div>
</div>
