{{--
    Ticket H11 — ajouts du poste à la modale « Déclarer une Saillie (Cuniculture) », après les champs du Blade et chez les
    lapins seulement (`_ouvrirDeclaration` / `_apercuEcheances`) :
    - « Cages Occupées » PRÉSENT ET DÉSACTIVÉ : aucun référentiel de cages ne peut porter la valeur ; la laisser
      saisissable la perdrait en silence (même constat qu'au ticket 3.10) ;
    - « Ligne du temps automatique calculée » depuis la date de saillie choisie : Palpation J+14, Boîte à nid J+28
      (jalon informatif), Mise bas J+30, Sevrage J+60.
    Reçoit : $saillieDate (Y-m-d, peut être vide pendant la saisie).
--}}
@php
    try {
        $origine = $saillieDate !== '' ? \Illuminate\Support\Carbon::parse($saillieDate)->startOfDay() : null;
    } catch (\Throwable) {
        $origine = null;
    }
    $echeance = fn (int $jours) => $origine?->copy()->addDays($jours)->format('d/m/Y') ?? '—';
@endphp
<div>
    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Cages Occupées</label>
    <input type="text" disabled placeholder="Référentiel des cages absent du schéma" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra text-outline cursor-not-allowed">
</div>
<div class="bg-info-blue/10 border border-info-blue/20 rounded-lg p-sm text-[10px] text-brand-forest">
    <p class="font-bold flex items-center gap-xs text-[11px]"><span class="material-symbols-outlined text-[14px]">calculate</span>Ligne du temps automatique calculée :</p>
    <div class="grid grid-cols-2 gap-x-sm mt-xs">
        <p>Palpation (J+14) : <span class="font-bold">{{ $echeance(14) }}</span></p>
        <p>Boîte à nid (J+28) : <span class="font-bold">{{ $echeance(28) }}</span></p>
        <p>Mise bas (J+30) : <span class="font-bold">{{ $echeance(30) }}</span></p>
        <p>Sevrage (J+60) : <span class="font-bold">{{ $echeance(60) }}</span></p>
    </div>
</div>
