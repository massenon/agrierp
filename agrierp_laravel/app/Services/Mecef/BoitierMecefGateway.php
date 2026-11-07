<?php

namespace App\Services\Mecef;

use App\Models\CreditNote;
use App\Models\Sale;
use App\Support\MecefEtat;

/**
 * MECEF-1 — SQUELETTE du mode boîtier (Eltrade CC300). Le boîtier est un serveur HTTP LOCAL (`http://localhost:38917`) :
 * le serveur hébergé ne peut pas l'atteindre, la transmission se fera PAR LE POSTE (ticket MECEF-2, non construit
 * faute de boîtier). Cette passerelle ne transmet RIEN : elle répond et laisse la vente « en attente ».
 */
class BoitierMecefGateway implements MecefAvoirGatewayInterface, MecefGatewayInterface
{
    public const MESSAGE = 'Mode boîtier : transmission par le poste non encore disponible.';

    public function transmit(Sale $sale): array
    {
        return $this->reponse();
    }

    public function transmitAvoir(CreditNote $avoir): array
    {
        return $this->reponse();
    }

    private function reponse(): array
    {
        return ['success' => false, 'qr_ref' => null, 'message' => self::MESSAGE, 'etat' => MecefEtat::EN_ATTENTE, 'details' => []];
    }
}
