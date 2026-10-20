{{--
    Ticket H11 — ajouts du poste à l'onglet Prévision (`_ongletPrevision`) : règle, sélecteur de bande, horizons, trois
    cartes (toujours rendues) et projection par horizon, sur la MÊME régression que le tableau du Blade.
    Reçoit : $choisie (?array, DashboardElevage::getPrevisionChoisieProperty), $projetables, $horizon.
    Le libellé « Calcul du poste … comme le serveur » est repris tel que le poste l'écrit (aucun libellé inventé).
--}}
@php
    $milliers = fn ($v) => number_format(round($v), 0, ',', ' ');
@endphp
<p class="text-xs text-outline">Calcul du poste : droite de régression sur toutes les pesées de la bande (trois au minimum), comme le serveur.</p>
<div class="bg-white border border-outline-variant rounded-lg p-md">
    <h3 class="text-sm font-bold text-brand-forest mb-md flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">tune</span>Paramètres de la projection</h3>
    @if($choisie === null)
        <p class="p-lg text-xs italic text-outline">— Trois pesées au minimum sont nécessaires pour projeter —</p>
    @else
        <div class="flex flex-wrap gap-md">
            <div class="w-full sm:w-80">
                <label class="block text-xs font-bold mb-xs">Bande</label>
                <select wire:model.live="bandePrevision" class="w-full h-10 px-md border border-outline-variant rounded-lg text-xs bg-white">
                    @foreach($projetables as $p)
                        <option value="{{ $p['lot']->id }}">{{ $p['lot']->code }} ({{ $p['lot']->species?->label }})</option>
                    @endforeach
                </select>
            </div>
            <div class="w-full sm:w-56">
                <label class="block text-xs font-bold mb-xs">Poids Actuel Constaté (g)</label>
                <input type="text" readonly value="{{ number_format($choisie['poids_actuel_g'], 0, '.', '') }}" class="w-full h-10 px-md border border-outline-variant rounded-lg text-xs bg-surface-zebra">
            </div>
            <div class="w-full sm:w-56">
                <label class="block text-xs font-bold mb-xs">GMQ Observé (g/jour)</label>
                <input type="text" readonly value="{{ number_format($choisie['pente'], 1, '.', '') }}" class="w-full h-10 px-md border border-outline-variant rounded-lg text-xs bg-surface-zebra">
            </div>
            <div class="w-full sm:w-56">
                <label class="block text-xs font-bold mb-xs">Horizon de Projection</label>
                <select wire:model.live="horizon" class="w-full h-10 px-md border border-outline-variant rounded-lg text-xs bg-white">
                    @foreach(\App\Livewire\Elevage\DashboardElevage::HORIZONS as $h)
                        <option value="{{ $h }}">{{ $h }} jours</option>
                    @endforeach
                </select>
            </div>
        </div>
    @endif
</div>

{{-- Les trois cartes, TOUJOURS rendues ; aucun poids cible n'est paramétré nulle part (ni web ni poste) : « — » expliqué, jamais un chiffre inventé. --}}
<div class="grid grid-cols-1 lg:grid-cols-3 gap-md">
    <x-kpi-card label="Poids Projeté" icon="trending_up" color="emerald"
        :value="$choisie === null ? '—' : $milliers(\App\Livewire\Elevage\DashboardElevage::projeter($choisie, $horizon)).' g'"
        :caption="$choisie === null ? 'Trois pesées au minimum' : 'À '.$horizon.' jours, '.$choisie['nb_pesees'].' pesées retenues'" />
    <x-kpi-card label="Poids Cible de Commercialisation" icon="flag" color="maize" value="—" caption="Aucun poids cible n'est paramétré" />
    <x-kpi-card label="Date Estimée d'Atteinte de la Cible" icon="event" color="maize" value="—" caption="Dépend du poids cible" />
</div>

@if($choisie !== null)
    {{-- Le poste rend la « courbe » en tableau, une ligne par horizon : même rendu ici. --}}
    <div class="bg-white border border-outline-variant rounded-lg p-md">
        <h3 class="text-sm font-bold text-brand-forest mb-md flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[18px]">show_chart</span>Courbe de Croissance — Historique et Projection</h3>
        <table class="w-full rtable text-xs">
            <thead class="bg-surface-zebra">
                <tr>
                    <th class="p-sm text-left text-[10px] text-outline font-bold uppercase">Échéance</th>
                    <th class="p-sm text-right text-[10px] text-outline font-bold uppercase">Poids (g)</th>
                </tr>
            </thead>
            <tbody>
                <tr class="rrow">
                    <td data-label="Échéance" class="p-sm font-bold">Aujourd'hui</td>
                    <td data-label="Poids (g)" class="p-sm text-right">{{ $milliers($choisie['poids_actuel_g']) }}</td>
                </tr>
                @foreach(\App\Livewire\Elevage\DashboardElevage::HORIZONS as $h)
                    <tr class="rrow {{ $h === $horizon ? 'font-bold' : '' }}">
                        <td data-label="Échéance" class="p-sm">+ {{ $h }} jours</td>
                        <td data-label="Poids (g)" class="p-sm text-right">{{ $milliers(\App\Livewire\Elevage\DashboardElevage::projeter($choisie, $h)) }}</td>
                    </tr>
                @endforeach
            </tbody>
        </table>
    </div>
@endif
