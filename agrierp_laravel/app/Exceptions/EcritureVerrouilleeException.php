<?php

namespace App\Exceptions;

/**
 * Tickets EX4 / EX5 (PRD exercices comptables) — une écriture du Journal ne peut pas être modifiée ou archivée :
 * à-nouveau (`ran`) ou sa contre-passation (`ran_reversal`), écriture verrouillée par la clôture, ou changement
 * d'exercice. Le message est rédigé pour l'utilisateur, en français, et affiché tel quel (toast du Journal).
 */
class EcritureVerrouilleeException extends \RuntimeException
{
}
