<?php

namespace App\Support;

use Illuminate\Support\Collection;
use Illuminate\Support\Str;

/**
 * Ticket 15.36 — CLÉ STABLE des catégories de rationnement des lapins.
 *
 * Le web retrouvait autrefois les rations par SOUS-CHAÎNE du libellé du
 * barème (`str_contains($r->stage_label, 'Sevré')`) avec des valeurs de
 * secours en dur (30 / 60 / 120). Renommer un libellé — ce que la décision
 * client du 14/10/2026 impose — faisait donc retomber EN SILENCE sur ces
 * constantes : aucun message, un chiffre qui a l'air juste tant que le barème
 * n'a pas été modifié, faux dès qu'il l'est.
 *
 * Le rapprochement passe désormais par trois CLÉS, indépendantes du texte
 * affiché :
 *
 *   reproducteur  → « Reproducteur »      (120 g/j)
 *   jeune         → « Jeune »             (30 g/j)  — ex-« Sevré »
 *   chair         → « Lapin de Chair »    (60 g/j)  — ex-« Jeune (engraissement) »
 *
 * ⚠️ Ces clés NE SONT PAS stockées : la clé est DÉDUITE du libellé, de façon
 * tolérante aux anciens ET aux nouveaux libellés (la base de production n'a
 * pas été vérifiée : elle peut porter l'un ou l'autre). Aucune colonne n'est
 * ajoutée, donc la forme de `/api/sync/pull` (`feed_ration_standards`) ne
 * change pas ; seule la VALEUR de `stage_label` peut changer (migration
 * 2026_10_14_000001).
 *
 * ⚠️ Ordre de test volontaire : « Jeune Lapin (engraissement) » contient
 * « Jeune » ; la clé `chair` doit donc être testée AVANT `jeune`, sinon
 * l'ancien libellé de la chair serait pris pour la catégorie Jeune.
 *
 * ⚠️ Ne PAS toucher aux colonnes `cat_eff_sevre` / `cat_eff_jeune` /
 * `effectif_sevres` : contrat /api/sync/* (cat_eff_sevre = Jeune,
 * cat_eff_jeune = Lapin de Chair, par historique).
 */
class CategorieRationLapin
{
    public const REPRODUCTEUR = 'reproducteur';
    public const JEUNE = 'jeune';
    public const CHAIR = 'chair';

    /** Valeurs de secours (g/j) — utilisées UNIQUEMENT si le barème ne porte pas la catégorie. */
    public const RATIONS_DE_SECOURS = [
        self::REPRODUCTEUR => 120,
        self::JEUNE => 30,
        self::CHAIR => 60,
    ];

    /** Libellés affichés (décision client du 14/10/2026). */
    public const LIBELLES = [
        self::REPRODUCTEUR => 'Reproducteur',
        self::JEUNE => 'Jeune',
        self::CHAIR => 'Lapin de Chair',
    ];

    /** Clé d'un libellé de barème (ancien ou nouveau), ou null s'il n'en relève pas. */
    public static function cle(?string $libelle): ?string
    {
        $l = Str::lower(Str::ascii(trim((string) $libelle)));

        if ($l === '') {
            return null;
        }

        if (str_contains($l, 'reproducteur')) {
            return self::REPRODUCTEUR;
        }

        // AVANT `jeune` : l'ancien « Jeune Lapin (engraissement) » contient « jeune ».
        if (str_contains($l, 'engraissement') || str_contains($l, 'chair')) {
            return self::CHAIR;
        }

        // « Lapin Sevré », « Sevré » (anciens) ou « Jeune » seul (nouveau).
        if (str_contains($l, 'sevre') || $l === 'jeune') {
            return self::JEUNE;
        }

        return null;
    }

    /**
     * Ration (g/j) d'une catégorie : celle du barème si elle existe, sinon la
     * valeur de secours.
     *
     * @param  Collection<int, object>  $rations  lignes de `feed_ration_standards`
     */
    public static function ration(Collection $rations, string $cle): int
    {
        $ligne = $rations->first(fn ($r) => self::cle($r->stage_label) === $cle);

        return (int) ($ligne->ration_g_per_day ?? self::RATIONS_DE_SECOURS[$cle]);
    }
}
