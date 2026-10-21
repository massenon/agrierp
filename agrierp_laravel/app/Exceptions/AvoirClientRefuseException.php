<?php

namespace App\Exceptions;

/**
 * Ticket AV1 — un retour client refusé AVANT toute écriture pour une raison qui n'est pas un champ du formulaire
 * (plan comptable incomplet). Le message est prêt à afficher : au web en toast, au poste comme motif de refus.
 */
class AvoirClientRefuseException extends \RuntimeException {}
