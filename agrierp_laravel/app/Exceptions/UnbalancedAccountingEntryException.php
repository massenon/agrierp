<?php

namespace App\Exceptions;

/**
 * Levée par `AccountingEntryService` dès que la somme des débits ne
 * correspond pas exactement à la somme des crédits — contrainte
 * critique (Document 03 §Contraintes applicatives, ticket 10.2).
 * Exception dédiée plutôt qu'une `\Exception` générique : un
 * déséquilibre comptable ne doit jamais être confondu avec une erreur
 * technique quelconque, ni silencieusement avalée par un `catch`
 * générique ailleurs dans l'application.
 */
class UnbalancedAccountingEntryException extends \RuntimeException
{
    public static function forTotals(float $totalDebit, float $totalCredit): self
    {
        return new self(sprintf(
            "Écriture comptable déséquilibrée : total débit %s FCFA ≠ total crédit %s FCFA. Aucune écriture n'a été enregistrée.",
            number_format($totalDebit, 2, ',', ' '),
            number_format($totalCredit, 2, ',', ' ')
        ));
    }
}
