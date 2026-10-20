<?php

namespace App\Exceptions;

use Carbon\Carbon;

/**
 * Ticket 10.6 (Sprint 10) — Document 01 §6.6 point 4 : "Toute tentative
 * d'écriture sur un exercice clos est bloquée côté serveur (pas
 * seulement côté UI) et journalisée." Levée par `AccountingEntryService`
 * quand la date d'une saisie tombe dans un exercice déjà clôturé.
 *
 * 🔴→✅ Ticket EX5 (règle R4 du PRD exercices comptables) — le message disait « Aucun exercice ouvert ne couvre la date
 * 2026-01-05 — l'écriture est refusée. » : date ISO, et il ne disait pas que l'exercice était CLOS. Désormais, au web
 * comme à l'envoi d'un poste : « L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 20/12/2026. »
 */
class ClosedFiscalYearException extends \RuntimeException
{
    public static function forDate(string $entryDate, int $annee): self
    {
        return new self(self::message($annee, Carbon::parse($entryDate)->format('d/m/Y')));
    }

    /** Le texte R4, seul point où il est écrit côté serveur. */
    public static function message(int $annee, string $jourFr): string
    {
        return "L'exercice {$annee} est clôturé : aucune saisie ne peut être datée du {$jourFr}.";
    }
}
