<?php

namespace App\Support;

/**
 * Ticket 15.39 — résultat PUR du calcul d'effectif par catégorie pour UNE journée.
 *
 * Emplacements génériques (14.11 / 14.12) : `repro` = Reproducteur ; `sevre` = Sous-mères (lapins) /
 * Porcelet (porcs) ; `jeune` = Jeune (lapins) / Marchand (porcs) — glossaire du 17/10/2026.
 *
 * ⚠️ `null` = INCONNU (une entrée du calcul n'est pas ventilée), jamais 0 : il s'affiche « — ».
 *
 * - `sommeDifferente` : true si la somme des trois catégories ≠ effectif total (avertissement D8,
 *   JAMAIS un blocage : le plancher à 0 de chaque catégorie suffit à la produire) ; null quand une
 *   catégorie ou le total est inconnu (rien à comparer).
 * - `refus` : motif français quand la saisie viole une règle (passage supérieur à la catégorie
 *   source, D3). Les catégories restent alors calculées avec le passage ramené à la source, de sorte
 *   qu'aucun sujet ne soit créé ; l'appelant qui SAISIT doit bloquer, l'appelant qui RECALCULE du
 *   stocké signale seulement.
 * - `passageApplique` : passage réellement transféré (≤ saisi), null si inconnu.
 */
final class EffectifCategoriesJour
{
    public function __construct(
        public readonly ?int $repro,
        public readonly ?int $sevre,
        public readonly ?int $jeune,
        public readonly ?bool $sommeDifferente,
        public readonly ?string $refus,
        public readonly ?int $passageApplique,
    ) {}

    /** @return array{cat_eff_repro: ?int, cat_eff_sevre: ?int, cat_eff_jeune: ?int} */
    public function versColonnes(): array
    {
        return ['cat_eff_repro' => $this->repro, 'cat_eff_sevre' => $this->sevre, 'cat_eff_jeune' => $this->jeune];
    }

    /** Somme des trois catégories, null si l'une est inconnue. */
    public function somme(): ?int
    {
        return ($this->repro === null || $this->sevre === null || $this->jeune === null)
            ? null
            : $this->repro + $this->sevre + $this->jeune;
    }

    public function estComplet(): bool
    {
        return $this->somme() !== null;
    }
}
