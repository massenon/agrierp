<?php

namespace App\Services\Mecef;

use App\Models\Sale;

/**
 * Implémentation dev/démo de `MecefGatewayInterface` (Document 06 §7).
 * Simule une transmission fiscale réussie et génère une référence NIM +
 * signature plausible (jamais un vrai identifiant délivré par la DGI —
 * ce projet n'a aucun accès au dispositif matériel/API réel). Utilisée
 * en environnement de développement et tant qu'aucune `RealMecefGateway`
 * n'est branchée.
 *
 * Simule occasionnellement un échec de transmission (aléatoire, rare)
 * pour permettre de tester réellement le statut "Erreur MeCeF" et
 * l'action de retransmission de l'écran Facturation — jamais 100% de
 * succès artificiel qui masquerait ce cas d'usage réel.
 */
class FakeMecefGateway implements MecefGatewayInterface
{
    public function transmit(Sale $sale): array
    {
        // Échec simulé occasionnel (~5%) — pour que le statut "Erreur MeCeF"
        // et l'action de retransmission restent réellement testables.
        if (random_int(1, 100) <= 5) {
            return [
                'success' => false,
                'qr_ref' => null,
                'message' => 'Délai de connexion dépassé avec le dispositif MeCeF (simulation).',
            ];
        }

        $nim = 'NIM-'.now()->format('Ymd').'-'.strtoupper(substr($sale->id, 0, 8));
        $signature = strtoupper(substr(hash('sha256', $sale->id.$sale->total.now()->timestamp), 0, 16));

        return [
            'success' => true,
            'qr_ref' => "{$nim}|{$signature}",
            'message' => 'Facture transmise avec succès au dispositif MeCeF (simulation dev).',
        ];
    }
}
