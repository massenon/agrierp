<?php

namespace App\Services\Mecef;

use App\Models\CreditNote;

/**
 * MECEF-1 — transmission d'un AVOIR (facture `FA`) dont la facture d'origine est normalisée. Interface à part : les
 * passerelles qui ne savent transmettre que des ventes (doublures de tests) restent valides ; une passerelle qui ne
 * l'implémente pas laisse l'avoir « en attente » avec son motif.
 *
 * Même forme de réponse que `MecefGatewayInterface::transmit()`.
 */
interface MecefAvoirGatewayInterface
{
    /** @return array{success: bool, qr_ref: ?string, message: string, etat?: string, details?: array<string, mixed>} */
    public function transmitAvoir(CreditNote $avoir): array;
}
