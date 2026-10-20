{{--
    Ticket H11 (décision D-H-maquette du 19/10/2026) — 4ᵉ ligne propre à chaque carte de filière, AJOUT DU POSTE construit
    au web. Les ajouts du poste vivent dans `ajouts-poste/` : les garde-fous du poste (`*_blade_test.dart`) lisent la vue
    principale comme le contrat d'origine du Blade et vérifient, eux, que le poste place ses ajouts APRÈS ce contrat.
    Reçoit : $ligne = [libellé, valeur].
--}}
<div class="flex justify-between"><span class="text-outline">{{ $ligne[0] }}</span><span class="font-bold {{ $ligne[1] === '—' ? 'text-outline' : '' }}">{{ $ligne[1] }}</span></div>
