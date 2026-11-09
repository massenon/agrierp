<?php

namespace App\Support;

/**
 * MECEF-1 — l'état MeCeF d'une vente ou d'un avoir, UN SEUL endroit pour ses clés et ses libellés.
 *
 * ⚠️ Les clés stockées sont celles d'avant MECEF-1 (1 500 occurrences dans les tests, le poste et les données déjà
 * semées) : `transmise` = « Normalisée », `erreur` = « Refusée ». Seule `expiree` est nouvelle.
 */
final class MecefEtat
{
    public const EN_ATTENTE = 'en_attente';

    public const NORMALISEE = 'transmise';

    public const REFUSEE = 'erreur';

    public const EXPIREE = 'expiree';

    public const LIBELLES = [
        self::NORMALISEE => 'Normalisée',
        self::EN_ATTENTE => 'En attente',
        self::REFUSEE => 'Refusée',
        self::EXPIREE => 'Expirée',
    ];

    public static function libelle(?string $etat): string
    {
        return self::LIBELLES[$etat ?? self::EN_ATTENTE] ?? 'En attente';
    }

    /** Une facture dans cet état peut être (re)transmise. */
    public static function retransmissible(?string $etat): bool
    {
        return $etat !== self::NORMALISEE;
    }
}
