{{--
    Ticket H11 (décision D-H-maquette du 19/10/2026) — en-têtes des colonnes AJOUTÉES du poste, après les neuf du Blade,
    dans leur ordre d'origine (Lapins : Sevrés (M/F), Morts S/Mère, Poids Moyen (g), Cages ; Porcs : Sevrage (J+42)).
    Les ajouts du poste vivent dans `ajouts-poste/` : `suivi_reproduction_blade_test.dart` (poste) lit la vue principale
    comme le contrat d'origine du Blade (neuf colonnes) et vérifie que le poste range ses ajouts APRÈS lui.
    Reçoit : $colonnes.
--}}
@foreach($colonnes as $colonne)
    <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">{{ $colonne }}</th>
@endforeach
