{{--
    Ticket EX8 (EF12) — bandeau d'une fiche d'élevage datée dans un exercice CLOS : la fiche se consulte, le formulaire
    est grisé. `$motif` : le message R4 du serveur (`AccountingEntryService::refusExerciceClos`), celui que `saveDay`
    renvoie déjà (EX5). Rien sinon.
    ⚠️ Le poste reprend ce bandeau mot pour mot (`LectureSeuleFiche`, `elements_fiche.dart`).
--}}
@props(['motif' => null])
@if($motif)
    <div class="bg-surface-zebra border border-outline-variant rounded-lg p-sm flex items-start gap-sm" data-lecture-seule>
        <span class="material-symbols-outlined text-outline text-[20px]">lock</span>
        <div>
            <p class="text-xs font-bold text-brand-forest">Lecture seule</p>
            <p class="text-[11px] text-on-surface mt-xs">{{ $motif }}</p>
        </div>
    </div>
@endif
