<?php

namespace App\Exceptions;

use Carbon\Carbon;

/**
 * Levée par `AccountingEntryService::exerciceOuvertPour()` quand AUCUN exercice ne couvre la date d'une saisie (et que
 * le filet R2 n'a pas pu l'ouvrir).
 *
 * 🔴→✅ Ticket EX5 (règle R4 du PRD exercices comptables) — le message disait « Aucun exercice comptable ouvert. Créez
 * ou rouvrez un exercice… » alors que des exercices ouverts existaient, et ne nommait ni la date ni l'exercice à
 * ouvrir. Il est désormais le même au web et à l'envoi d'un poste, la date au format JJ/MM/AAAA :
 * « Aucun exercice comptable ne couvre le 10/01/2027. Ouvrez l'exercice 2027 (Comptabilité › Clôture d'exercice). »
 * Le poste en garde une copie mot pour mot (`caisse_repository.dart`, `refusDeDate`).
 */
class NoOpenFiscalYearException extends \RuntimeException
{
    public function __construct(?string $message = null)
    {
        parent::__construct($message ?? "Aucun exercice comptable ne couvre cette date. Ouvrez l'exercice (Comptabilité › Clôture d'exercice).");
    }

    public static function pourDate(string $date): self
    {
        $jour = Carbon::parse($date);

        return new self(self::message($jour->format('d/m/Y'), (int) $jour->format('Y')));
    }

    /** Le texte R4, seul point où il est écrit côté serveur. */
    public static function message(string $jourFr, int $annee): string
    {
        return "Aucun exercice comptable ne couvre le {$jourFr}. Ouvrez l'exercice {$annee} (Comptabilité › Clôture d'exercice).";
    }
}
