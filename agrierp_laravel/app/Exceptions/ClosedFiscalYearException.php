<?php

namespace App\Exceptions;

/**
 * Ticket 10.6 (Sprint 10) — Document 01 §6.6 point 4 : "Toute tentative
 * d'écriture sur un exercice clos est bloquée côté serveur (pas
 * seulement côté UI) et journalisée." Levée par `AccountingEntryService`
 * quand la date d'une écriture tombe dans un exercice déjà clôturé, ou
 * qu'aucun exercice ne couvre cette date.
 */
class ClosedFiscalYearException extends \RuntimeException
{
    public static function forDate(string $entryDate): self
    {
        return new self("Aucun exercice ouvert ne couvre la date {$entryDate} — l'écriture est refusée.");
    }
}
