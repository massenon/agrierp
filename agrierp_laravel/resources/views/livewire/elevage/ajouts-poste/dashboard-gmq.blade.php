{{--
    Ticket H11 — cartes et courbe de l'onglet GMQ (ajouts du poste), sur le MÊME GMQ cumulé que le tableau du Blade.
    Reçoit : $cartes (DashboardElevage::getGmqCartesProperty), $suivie (?LivestockLot), $evolution (8 points).
    Valeur écrite sans décimale (`toStringAsFixed(0)` du poste) ; objectifs = constantes du poste (OBJECTIFS_GMQ).
--}}
@php
    $carteGmq = function (string $code) use ($cartes) {
        $v = $cartes['par_espece'][$code];
        [$min, $max] = \App\Livewire\Elevage\DashboardElevage::OBJECTIFS_GMQ[$code];

        return $v === null
            ? ['—', 'Moins de 2 pesées enregistrées']
            : [number_format($v, 0, '.', '').' g/j', 'Objectif : '.$min.'-'.$max.' g/j'];
    };
    [$lapV, $lapC] = $carteGmq('cuniculture');
    [$aviV, $aviC] = $carteGmq('aviculture');
    [$porV, $porC] = $carteGmq('porciculture');
@endphp
<div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
    <x-kpi-card label="GMQ Moyen Lapins" icon="trending_up" color="emerald" :value="$lapV" :caption="$lapC" />
    <x-kpi-card label="GMQ Moyen Volailles Chair" icon="trending_up" color="maize" :value="$aviV" :caption="$aviC" />
    <x-kpi-card label="GMQ Moyen Porcs" icon="trending_up" color="red" :value="$porV" :caption="$porC" />
    <x-kpi-card label="Lots Suivis (Pesées ≥ 2)" icon="checklist" color="blue" :value="$cartes['lots_suivis']" />
</div>
<div class="bg-white border border-outline-variant rounded-lg p-md">
    <h3 class="text-sm font-bold text-brand-forest mb-md">{{ $suivie === null ? 'Évolution du GMQ — 8 dernières semaines' : 'Évolution du GMQ — '.$suivie->code.' (8 dernières semaines)' }}</h3>
    <x-courbe-gmq :series="['suivie' => $evolution]" />
</div>
