<?php

namespace App\Exceptions;

/**
 * Ticket 15.22 — un achat (direct, reçu d'un bon de commande, ou rejoué depuis un poste) qui ne peut PAS passer son
 * écriture est REFUSÉ en bloc : compte du plan comptable manquant, ou montant nul. Hérite de `\DomainException`
 * (c'est ce que levait déjà la réception, ticket 15.21) : les appelants existants restent valides.
 * Le refus d'un exercice clos/absent reste porté par `ClosedFiscalYearException` / `NoOpenFiscalYearException`.
 */
class AchatNonComptabilisableException extends \DomainException
{
    public static function compteManquant(): self
    {
        return new self("Écriture comptable impossible (compte 601, 445, 401 ou compte de trésorerie absent du plan comptable) : l'achat est annulé, aucun stock ni dette n'a été enregistré.");
    }

    public static function montantNul(): self
    {
        return new self("Un achat dont le total est nul ne peut pas être enregistré : il ne produirait aucune écriture comptable. Renseignez les prix d'achat.");
    }
}
