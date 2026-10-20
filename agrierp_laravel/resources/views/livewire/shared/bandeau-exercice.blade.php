{{--
    Ticket EX7 (EF10, PRD § 7) — bandeau de lecture seule de l'exercice AFFICHÉ quand il est clos, en haut du contenu.
    Le composant partagé `x-bandeau-lecture-seule` (le même que celui des fiches d'élevage, EX8) porte le texte et le
    lien. Le poste reprend ce texte mot pour mot (`agrierp_flutter/lib/core/widgets/bandeau_exercice.dart`).
--}}
<div>
    <x-bandeau-lecture-seule :bandeau="$bandeau" action="passer" class="mb-lg" />
</div>
