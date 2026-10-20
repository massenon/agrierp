<?php

namespace App\Support;

use Carbon\Carbon;

/**
 * Ticket EX8 (EF11, PRD `docs/prd/exercices-comptables.md` § 7) — présentation des colonnes « Exercice N » /
 * « Exercice N-1 » du Bilan et du Compte de résultat (écran Bilan, États financiers, leurs PDF). Un seul endroit écrit
 * les en-têtes et les montants des deux colonnes.
 *
 * ⚠️ Le poste reprend ces textes mot pour mot (`agrierp_flutter/lib/features/comptabilite/etats_comparatifs.dart`),
 * vérifiés par une parité EXÉCUTÉE (`test/comparatif_n_moins_un_parite_test.dart` appelle cette classe).
 */
final class ComparatifNMoinsUn
{
    public const ENTETE_N = 'Exercice N';

    public const ENTETE_N1 = 'Exercice N-1';

    /** Sous-titre de la colonne N-1 quand l'exercice précédent n'existe pas. */
    public const SANS_EXERCICE = 'Aucun exercice antérieur';

    /** Montant d'une colonne : « — » quand l'exercice n'existe pas (`null`), JAMAIS 0 ; sinon arrondi au franc. */
    public static function montant(?float $valeur): string
    {
        if ($valeur === null) {
            return '—';
        }

        // `+ 0.0` : un -0 (solde arrondi à zéro, capitaux affichés en négatif) s'écrit « 0 », jamais « -0 ».
        return number_format(round($valeur) + 0.0, 0, ',', ' ');
    }

    /** Sous-titre d'une colonne : « 2027 — au 31/01/2027 », ou « Aucun exercice antérieur ». */
    public static function sousTitre(?array $exercice): string
    {
        if ($exercice === null) {
            return self::SANS_EXERCICE;
        }

        return $exercice['annee'].' — au '.Carbon::parse($exercice['arrete'])->format('d/m/Y');
    }
}
