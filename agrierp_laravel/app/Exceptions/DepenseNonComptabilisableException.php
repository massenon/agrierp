<?php

namespace App\Exceptions;

/**
 * Ticket DEP1 — la pièce d'une dépense ne peut pas être passée (compte de trésorerie sans compte du plan comptable,
 * montant nul). La dépense n'est alors PAS enregistrée : tout est annulé, jamais une dépense sans pièce. Message déjà
 * rédigé pour l'utilisateur ; repris tel quel comme motif de refus de l'envoi d'un poste.
 */
class DepenseNonComptabilisableException extends \RuntimeException
{
}
