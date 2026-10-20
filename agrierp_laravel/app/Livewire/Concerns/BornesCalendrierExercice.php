<?php

namespace App\Livewire\Concerns;

use App\Services\AccountingEntryService;

/**
 * Ticket EX6 (EF7 du PRD exercices comptables) — les calendriers des saisies datées sont BORNÉS aux exercices ouverts
 * connus, comme celui de la caisse (15.32) : l'utilisateur ne choisit plus un jour que le serveur refusera. Bornes
 * indicatives : le serveur re-juge tout (`AccountingEntryService::exerciceOuvertPour` / `refusExerciceClos`).
 * Utilisé par la Saisie des Dépenses, les Dettes Fournisseurs, la Liste d'Achats (remboursement), l'Historique des
 * Avances et la Gestion des Stocks (ajout). Le poste a les mêmes bornes (`ExerciceDeSaisie::premierJour`).
 */
trait BornesCalendrierExercice
{
    /** Saisie qui passe une écriture : début du plus ancien exercice OUVERT (`null` : aucun, pas de borne). */
    public function getDateMinSaisieProperty(): ?string
    {
        return app(AccountingEntryService::class)->premierJourSaisissable();
    }

    /** Saisie jugée « exercice clos seulement » (ajout de stock) : lendemain du dernier exercice CLOS. */
    public function getDateMinHorsExerciceClosProperty(): ?string
    {
        return app(AccountingEntryService::class)->premierJourHorsExerciceClos();
    }
}
