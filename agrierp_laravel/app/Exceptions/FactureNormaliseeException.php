<?php

namespace App\Exceptions;

/**
 * MECEF-1 — une facture NORMALISÉE (déclarée à la DGI) n'est ni modifiable ni annulable : la correction passe par un
 * avoir lié à la facture d'origine. Le message est prêt à afficher (toast au web, motif de refus au poste).
 */
class FactureNormaliseeException extends \RuntimeException
{
    public const MESSAGE = 'Facture normalisée : corrigez-la par un avoir.';

    public function __construct(string $message = self::MESSAGE)
    {
        parent::__construct($message);
    }
}
