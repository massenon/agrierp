<?php

namespace App\Support;

/**
 * Le type de facture choisi à la vente — UN SEUL endroit pour ses clés et ses libellés (web, poste, serveur).
 *
 * `simple` (défaut) : jamais transmise à la DGI, aucun QR ; une correction se fait par avoir. `normalisee` : transmise
 * à e-MECeF (module actif), verrouillée une fois normalisée (MECEF-1).
 */
final class FactureType
{
    public const SIMPLE = 'simple';

    public const NORMALISEE = 'normalisee';

    public const LIBELLES = [
        self::SIMPLE => 'Facture simple',
        self::NORMALISEE => 'Facture normalisée',
    ];

    /** Mention imprimée sur une facture simple (web `exports.facture-vente`, poste `DocumentsFacturation.facture`). */
    public const MENTION_SIMPLE = 'Facture simple — non normalisée DGI';

    /** Mention d'une facture normalisée demandée mais pas encore certifiée (rien d'inventé : pas de QR ni de code). */
    public const MENTION_EN_ATTENTE = 'Facture normalisée demandée — en attente';
}
