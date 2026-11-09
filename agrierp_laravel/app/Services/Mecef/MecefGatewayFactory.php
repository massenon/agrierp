<?php

namespace App\Services\Mecef;

use App\Support\MecefMode;

/**
 * MECEF-1 — LA FABRIQUE UNIQUE de la passerelle, selon le mode réglé (remplace le `bind` fixe sur `FakeMecefGateway`).
 * Résolue à CHAQUE demande : changer de mode dans Paramètres s'applique à la transmission suivante.
 */
class MecefGatewayFactory
{
    public static function make(): MecefGatewayInterface
    {
        return match (app(MecefReglage::class)->mode()) {
            MecefMode::EMECEF => app(EmecefGateway::class),
            MecefMode::BOITIER => app(BoitierMecefGateway::class),
            MecefMode::SIMULE => app(FakeMecefGateway::class),
            default => new class implements MecefGatewayInterface
            {
                // Module désactivé : `FacturationMecefService` ne l'appelle jamais ; ce garde-fou refuse sans rien déclarer.
                public function transmit(\App\Models\Sale $sale): array
                {
                    return ['success' => false, 'qr_ref' => null, 'message' => 'Module MeCeF désactivé.', 'etat' => 'en_attente'];
                }
            },
        };
    }
}
