<?php

namespace App\Exceptions;

/**
 * Levée par `AccountingEntryService` quand aucun `FiscalYear` au statut
 * `ouvert` n'existe — une écriture comptable ne peut jamais être créée
 * sans exercice ouvert pour la porter (Sprint 10, ticket 10.2 ; la
 * clôture réelle d'exercice arrive au ticket 10.6).
 */
class NoOpenFiscalYearException extends \RuntimeException
{
    public function __construct()
    {
        parent::__construct("Aucun exercice comptable ouvert. Créez ou rouvrez un exercice avant d'enregistrer une écriture.");
    }
}
