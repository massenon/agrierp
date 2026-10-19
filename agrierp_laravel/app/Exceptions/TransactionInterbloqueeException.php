<?php

namespace App\Exceptions;

/**
 * Ticket S-T13 — une transaction rejouée par `TransactionRejouable` est restée interbloquée (MariaDB 1213) ou en
 * attente de verrou (1205) à chacun de ses essais. Chaque essai a été annulé : RIEN n'a été écrit. Le message est déjà
 * rédigé pour l'utilisateur, en français ; l'exception de la base du dernier essai est gardée en `getPrevious()`.
 */
class TransactionInterbloqueeException extends \RuntimeException
{
    public function __construct(public readonly int $essais, \Throwable $derniere)
    {
        parent::__construct(
            "La base de données est occupée par d'autres enregistrements simultanés : opération annulée après "
            .$essais.' essais, rien n\'a été enregistré. Réessayez dans un instant.',
            0,
            $derniere,
        );
    }
}
