<?php

namespace App\Exceptions;

/**
 * Ticket U14 — une dépense ne peut pas être modifiée (déjà comptabilisée, ou archivée). Le message est DÉJÀ rédigé
 * pour l'utilisateur, en français : il est affiché sous le champ « Montant » de « Saisie des Dépenses » (web) et repris
 * tel quel comme motif de refus de l'envoi d'un poste (le poste l'affiche aussi sous ce champ, avant d'écrire).
 */
class DepenseNonModifiableException extends \RuntimeException
{
}
