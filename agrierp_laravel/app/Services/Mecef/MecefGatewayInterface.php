<?php

namespace App\Services\Mecef;

use App\Models\Sale;

/**
 * Ticket 7.1 (Sprint 7) — Document 06 §7 (directive explicite du projet) :
 * "Prévoir une interface MecefGatewayInterface avec FakeMecefGateway
 * (dev/démo) et RealMecefGateway (à brancher plus tard sans changer le
 * reste du code)."
 *
 * MeCeF (Machine Électronique Certifiée de Facturation) est le dispositif
 * de certification fiscale de la DGI (Direction Générale des Impôts,
 * Bénin) — l'intégration réelle nécessite un identifiant NIM et des
 * accès matériels/API délivrés par l'administration fiscale, qui
 * n'existent pas dans ce projet. `RealMecefGateway` n'est PAS implémentée
 * (aucun accès réel disponible) ; seule cette interface et
 * `FakeMecefGateway` (simulation dev/démo) existent pour l'instant —
 * exactement le périmètre demandé par la directive, ni plus ni moins.
 * Le reste de l'application (POS, Facturation) dépend uniquement de ce
 * contrat, jamais de l'implémentation concrète — brancher
 * `RealMecefGateway` le jour venu ne touchera aucun autre fichier.
 */
interface MecefGatewayInterface
{
    /**
     * Transmet une vente au dispositif MeCeF.
     *
     * MECEF-1 : la réponse peut porter, EN PLUS, `etat` (`MecefEtat` : `en_attente` = à retenter, `erreur` = refusée,
     * `expiree`) quand la transmission n'a pas abouti — sans lui, un échec est « refusée » comme avant — et `details`
     * (`uid`, `code`, `nim`, `compteurs`, `date`) : ce que la DGI a renvoyé, y compris l'`uid` d'une facture créée mais
     * pas encore confirmée.
     *
     * @return array{success: bool, qr_ref: ?string, message: string, etat?: string, details?: array<string, mixed>}
     */
    public function transmit(Sale $sale): array;
}
