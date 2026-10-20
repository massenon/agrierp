{{--
    Ticket EX2 — mention « À-nouveaux provisoires » (PRD `docs/prd/exercices-comptables.md`, R3 et § 7), sous le titre de
    chaque état dont l'ouverture est CALCULÉE parce que l'exercice précédent est encore ouvert.
    `$ouverture` : `FinancialReportService::resumeOuverture()` (`provisoire`, `annee`, `precedent`) ; rien sinon.
    ⚠️ Le poste reprend ce texte mot pour mot (`agrierp_flutter/lib/features/comptabilite/mention_anouveaux.dart`,
    vérifié par `test/bascule_exercice_parite_test.dart`, qui lit CE fichier).
--}}
@props(['ouverture' => null])
@if(($ouverture['provisoire'] ?? false) === true)
    <div class="bg-accent-yellow/10 border border-accent-yellow rounded-lg p-sm mb-lg flex items-start gap-sm" data-anouveaux-provisoires>
        <span class="material-symbols-outlined text-brand-forest text-[20px]">hourglass_empty</span>
        <div>
            <p class="text-xs font-bold text-brand-forest">À-nouveaux provisoires</p>
            <p class="text-[11px] text-on-surface mt-xs">L'exercice {{ $ouverture['precedent'] }} n'est pas clôturé : l'ouverture de l'exercice {{ $ouverture['annee'] }} est calculée à partir de ses soldes au 31/12/{{ $ouverture['precedent'] }}, avec le résultat de l'exercice {{ $ouverture['precedent'] }} (provisoire). Elle suit toute écriture passée en {{ $ouverture['precedent'] }} ; à la clôture, l'à-nouveau définitif la remplace sans changer aucun chiffre.</p>
        </div>
    </div>
@endif
