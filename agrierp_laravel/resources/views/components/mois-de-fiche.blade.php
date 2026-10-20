{{--
    Ticket EX8 (EF12, PRD `docs/prd/exercices-comptables.md` § 4) — navigation de mois des cinq fiches d'élevage :
    « ‹ » mois précédent, le mois affiché, « › » mois suivant (grisé sur le mois en cours : pas de mois à venir).
    Le composant Livewire porte `moisPrecedent` / `moisSuivant` (`Concerns\AvecMoisDeFiche`).
    ⚠️ Le poste reprend ces libellés mot pour mot (`agrierp_flutter/lib/features/elevage/elements_fiche.dart`,
    `MoisDeFiche`), vérifiés par `test/fiches_mois_passes_test.dart`, qui lit CE fichier.
--}}
@props(['libelle', 'courant' => false])
<span class="text-xs text-outline font-semibold">Mois :</span>
<div class="flex items-center h-9 border border-outline-variant rounded-lg bg-surface-zebra overflow-hidden" data-mois-de-fiche>
    <button type="button" wire:click="moisPrecedent" title="Mois précédent" aria-label="Mois précédent" class="w-8 h-9 flex items-center justify-center text-brand-forest hover:bg-brand-emerald/10">
        <span class="material-symbols-outlined text-[18px]">chevron_left</span>
    </button>
    <span class="px-sm text-xs font-bold text-brand-forest whitespace-nowrap">{{ $libelle }}</span>
    <button type="button" wire:click="moisSuivant" title="Mois suivant" aria-label="Mois suivant" @disabled($courant) class="w-8 h-9 flex items-center justify-center text-brand-forest hover:bg-brand-emerald/10 disabled:opacity-40 disabled:cursor-not-allowed">
        <span class="material-symbols-outlined text-[18px]">chevron_right</span>
    </button>
</div>
