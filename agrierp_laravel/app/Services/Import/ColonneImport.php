<?php

namespace App\Services\Import;

/**
 * Ticket IMPORT-1 — une colonne d'un modèle d'importation.
 *
 * `type` : `texte`, `telephone` (texte : le zéro initial ne se perd pas), `code` (texte : numéro de compte, zéros conservés),
 * `date` (texte AAAA-MM-JJ : jamais convertie en date Excel), `entier` (FCFA entiers), `decimal` (virgule ou point), `liste`
 * (valeur de la liste déroulante `liste`).
 */
final class ColonneImport
{
    public function __construct(
        public readonly string $cle,
        public readonly string $libelle,
        public readonly bool $obligatoire,
        public readonly string $type,
        public readonly string $aide,
        public readonly ?string $liste = null,
    ) {
    }

    /** En-tête EXACT du fichier : le libellé, suivi de « * » quand la colonne est obligatoire. */
    public function entete(): string
    {
        return $this->libelle.($this->obligatoire ? ' *' : '');
    }

    public function formatLisible(): string
    {
        return match ($this->type) {
            'telephone' => 'Texte (le zéro initial est conservé)',
            'code' => 'Texte (les zéros initiaux sont conservés)',
            'date' => 'Date au format AAAA-MM-JJ (exemple : 2026-11-08)',
            'entier' => 'Nombre entier de FCFA, sans décimale ni séparateur',
            'decimal' => 'Nombre (virgule ou point)',
            'liste' => 'Valeur de la liste déroulante',
            default => 'Texte',
        };
    }
}
