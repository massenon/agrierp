<?php

namespace App\Services\Mecef;

use App\Models\CreditNote;
use App\Models\Sale;
use App\Support\MecefEtat;

/**
 * MECEF-1 / MECEF-2 — le mode boîtier (Eltrade CC300). Le boîtier est un serveur HTTP LOCAL (`http://localhost:38917`) :
 * le serveur hébergé ne peut pas l'atteindre, la transmission se fait PAR LE POSTE (MECEF-2, construit sans appareil :
 * NON VÉRIFIÉ AVEC UN VRAI BOÎTIER). Cette passerelle ne transmet RIEN : elle garde la vente « en attente » ; le poste
 * transmet puis envoie le résultat avec la vente (`ResultatBoitierDuPoste`, appliqué par `SyncController::pushSales`).
 */
class BoitierMecefGateway implements MecefAvoirGatewayInterface, MecefGatewayInterface
{
    public const MESSAGE = 'Mode boîtier : la facture attend sa transmission par le poste (le boîtier est branché sur le poste).';

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
