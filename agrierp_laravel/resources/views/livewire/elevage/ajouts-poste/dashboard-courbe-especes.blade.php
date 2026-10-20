{{--
    Ticket H11 — courbe hebdomadaire du GMQ cumulé par espèce (ajout du poste, `_courbeEspeces`), sous la grille
    « Résumé / Rappels » de la Synthèse. Reçoit : $series (DashboardElevage::getGmqParEspeceParSemaineProperty).
--}}
<div class="bg-white border border-outline-variant rounded-lg p-md">
    <h3 class="text-sm font-bold text-brand-forest mb-md">Croissance (GMQ) par Espèce - 4 dernières semaines</h3>
    <x-courbe-gmq :series="$series" />
    <div class="flex items-center gap-lg mt-sm text-xs">
        <span class="flex items-center gap-xs text-outline"><span class="w-3 h-3 rounded-full bg-brand-emerald inline-block"></span>Cuniculture</span>
        <span class="flex items-center gap-xs text-outline"><span class="w-3 h-3 rounded-full bg-info-blue inline-block"></span>Aviculture</span>
        <span class="flex items-center gap-xs text-outline"><span class="w-3 h-3 rounded-full bg-accent-yellow inline-block"></span>Porciculture</span>
    </div>
</div>
