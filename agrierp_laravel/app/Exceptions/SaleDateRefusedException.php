<?php

namespace App\Exceptions;

/**
 * Ticket 15.30 — la date d'une vente est refusée (futur, mois clôturé, exercice
 * absent ou clos). Le message est DÉJÀ rédigé pour l'utilisateur, en français :
 * il est repris tel quel comme motif de rejet au push et en erreur au POS web.
 */
class SaleDateRefusedException extends \RuntimeException
{
}
