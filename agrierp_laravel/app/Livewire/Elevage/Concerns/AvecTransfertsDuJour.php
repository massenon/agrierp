<?php

namespace App\Livewire\Elevage\Concerns;

use App\Models\LivestockDailyEntry;

/**
 * Ticket 15.46 — TRANSFERTS ENTRE BANDES DU JOUR AFFICHÉ, pour les cinq fiches journalières.
 *
 * Les colonnes `transfert_*` de la fiche sont dérivées de `livestock_transfers` (écran Transferts entre Bandes) :
 * la fiche ne les saisit pas, mais son effectif du jour DOIT les compter. Sans elles, ressaisir la fiche d'un jour
 * de transfert écrivait un effectif qui ignorait le transfert, et la cascade repartait de ce faux point de départ.
 *
 * La fiche utilisatrice fournit `bandeDeLaFiche()` et `$selectedDate`.
 */
trait AvecTransfertsDuJour
{
    /** @return array<string, int> colonnes `transfert_*` de la fiche (bande, jour) ; 0 sans fiche ni transfert. */
    public function getTransfertsDuJourProperty(): array
    {
        $colonnes = [
            'transfert_entree', 'transfert_sortie',
            'transfert_entree_repro', 'transfert_entree_sevre', 'transfert_entree_jeune',
            'transfert_sortie_repro', 'transfert_sortie_sevre', 'transfert_sortie_jeune',
        ];

        $bande = $this->bandeDeLaFiche();
        $fiche = $bande && $this->selectedDate
            ? LivestockDailyEntry::where('lot_id', $bande->id)->whereDate('entry_date', $this->selectedDate)->first()
            : null;

        return collect($colonnes)->mapWithKeys(fn ($c) => [$c => (int) ($fiche?->{$c} ?? 0)])->all();
    }
}
