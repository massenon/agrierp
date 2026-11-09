<?php

namespace App\Exceptions;

/** MECEF-1 — une vente ou un avoir qui ne peut pas être exprimé en facture e-MECeF (taux de TVA inconnu, montant nul…). Message français. */
class MecefFactureInvalideException extends \RuntimeException {}
