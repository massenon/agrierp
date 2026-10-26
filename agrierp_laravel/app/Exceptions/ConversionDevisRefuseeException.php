<?php

namespace App\Exceptions;

/**
 * Ticket DEV3 — la conversion d'un devis en facture est refusée AVANT toute écriture (statut non convertible, devis
 * archivé ou inconnu, client absent ou archivé, exercice clos, plan comptable incomplet). Le message est prêt à
 * afficher : au web en toast d'erreur, au poste comme motif de refus de la demande.
 */
class ConversionDevisRefuseeException extends \RuntimeException {}
