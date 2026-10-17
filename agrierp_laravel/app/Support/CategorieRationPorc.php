<?php

namespace App\Support;

use Illuminate\Support\Collection;
use Illuminate\Support\Str;

/**
 * Ticket 15.42 — CLÉ STABLE des catégories de rationnement des PORCS (miroir de `CategorieRationLapin`, ticket 15.36).
 *
 * Le web retrouvait autrefois les rations par SOUS-CHAÎNE SENSIBLE À LA CASSE du libellé du barème
 * (`str_contains($r->stage_label, 'reproducteur')`, `'Jeune'`, `'Porcelet'`) avec des valeurs de secours en dur
 * (2 000 / 300 / 600). Un libellé « Reproducteur » (maquette) ou « Porc Marchand » (maquette, D15) ne correspondait à
 * AUCUN fragment : la fiche retombait EN SILENCE sur la constante — aucun message, un chiffre qui a l'air juste tant
 * que le barème n'a pas été modifié, faux dès qu'il l'est.
 *
 * Le rapprochement passe désormais par trois CLÉS, indépendantes du texte affiché ET de sa casse :
 *
 *   reproducteur → « Reproducteur »   (2 000 g/j)   barème : « Porc reproducteur »
 *   porcelet     → « Porcelet »       (300 g/j)     barème : « Porcelet »
 *   marchand     → « Porc Marchand »  (600 g/j)     barème : « Jeune porc » (D15, NON renommé)
 *
 * ⚠️ D15 (décision client à confirmer) : la maquette dit « Porc Marchand », le barème de la base dit « Jeune porc ».
 * La donnée du barème n'est PAS renommée ici : la clé les reconnaît tous les deux, ainsi que « Jeune marchand »
 * (ancien libellé de tests), « Engraissement » et « Jeune » seul. L'écran affiche le libellé de la maquette.
 *
 * ⚠️ Ces clés NE SONT PAS stockées : la clé est DÉDUITE du libellé. Aucune colonne n'est ajoutée, la forme de
 * `/api/sync/pull` (`feed_ration_standards`) ne change pas.
 *
 * ⚠️ Ordre de test volontaire : « reproducteur » avant « porcelet » avant « marchand ». Une ligne sans rapport
 * (« Lapin Sevré », « Jeunes », « Truie ») n'a AUCUNE clé : elle ne vole jamais la ration d'une catégorie.
 */
class CategorieRationPorc
{
    public const REPRODUCTEUR = 'reproducteur';

    public const PORCELET = 'porcelet';

    public const MARCHAND = 'marchand';

    /** Valeurs de secours (g/j) — utilisées UNIQUEMENT si le barème ne porte pas la catégorie. */
    public const RATIONS_DE_SECOURS = [
        self::REPRODUCTEUR => 2000,
        self::PORCELET => 300,
        self::MARCHAND => 600,
    ];

    /** Libellés affichés (maquette `fiche-porcs.html`). */
    public const LIBELLES = [
        self::REPRODUCTEUR => 'Reproducteur',
        self::PORCELET => 'Porcelet',
        self::MARCHAND => 'Porc Marchand',
    ];

    /** Clé d'un libellé de barème (ancien ou nouveau, casse et accents indifférents), ou null s'il n'en relève pas. */
    public static function cle(?string $libelle): ?string
    {
        $l = Str::lower(Str::ascii(trim((string) $libelle)));

        if ($l === '') {
            return null;
        }

        if (str_contains($l, 'reproducteur')) {
            return self::REPRODUCTEUR;
        }

        if (str_contains($l, 'porcelet')) {
            return self::PORCELET;
        }

        // « Porc Marchand », « Jeune marchand », « Jeune porc (Engraissement) », « Engraissement » ; « Jeune » / « Jeune porc » seuls.
        if (str_contains($l, 'marchand') || str_contains($l, 'engraissement') || preg_match('/^jeune( porc)?$/', $l) === 1) {
            return self::MARCHAND;
        }

        return null;
    }

    /**
     * Ration (g/j) d'une catégorie : celle du barème si elle existe, sinon la valeur de secours.
     *
     * @param  Collection<int, object>  $rations  lignes de `feed_ration_standards`
     */
    public static function ration(Collection $rations, string $cle): int
    {
        $ligne = $rations->first(fn ($r) => self::cle($r->stage_label) === $cle);

        return (int) ($ligne->ration_g_per_day ?? self::RATIONS_DE_SECOURS[$cle]);
    }
}
