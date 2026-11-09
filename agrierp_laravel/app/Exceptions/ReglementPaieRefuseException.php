<?php

namespace App\Exceptions;

use RuntimeException;

/** Ticket RH-4 — règlement de paie refusé pour une raison métier (employé archivé) ; le message s'affiche tel quel. */
class ReglementPaieRefuseException extends RuntimeException {}
