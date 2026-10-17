<?php

namespace App\Support;

use Illuminate\Support\Collection;
use Illuminate\Support\Str;

/**
 * Ticket 15.36 — CLÉ STABLE des catégories de rationnement des lapins.
 *
 * Le web retrouvait autrefois les rations par SOUS-CHAÎNE du libellé du
 * barème avec des valeurs de secours en dur : renommer un libellé faisait
 * retomber EN SILENCE sur ces constantes. Le rapprochement passe par trois
 * CLÉS, indépendantes du texte affiché.
 *
 * 🔁 DÉCISION CLIENT DU 17/10/2026 (remplace celle du 14/10/2026) — glossaire
 * des lapins : Reproducteur / Jeune / Sous-mères, partout (morts, dons,
 * départ, rationnement, stade de la bande).
 *
 *   reproducteur  → « Reproducteur »  (120 g/j)
 *   sous_meres    → « Sous-mères »    (30 g/j)  — ex-« Jeune » (14/10), ex-« Sevré »
 *   chair         → « Jeune »         (60 g/j)  — ex-« Lapin de Chair », ex-« Jeune (engraissement) »
 *
 * ⚠️ « Jeune » change donc de catégorie : le 14/10 il désignait les 30 g/j,
 * il désigne désormais les 60 g/j. La migration 2026_10_17_000001 renomme le
 * barème dans le bon ordre (Jeune → Sous-mères, PUIS Lapin de Chair → Jeune).
 *
 * ⚠️ Emplacements de synchronisation INCHANGÉS : `*_sevre` = Sous-mères,
 * `*_jeune` = Jeune (contrat /api/sync/*).
 */
class CategorieRationLapin
{
    public const REPRODUCTEUR = 'reproducteur';

    public const SOUS_MERES = 'sous_meres';

    public const CHAIR = 'chair';

    /** Valeurs de secours (g/j) — utilisées UNIQUEMENT si le barème ne porte pas la catégorie. */
    public const RATIONS_DE_SECOURS = [
        self::REPRODUCTEUR => 120,
        self::SOUS_MERES => 30,
        self::CHAIR => 60,
    ];

    /** Libellés affichés (décision client du 17/10/2026). */
    public const LIBELLES = [
        self::REPRODUCTEUR => 'Reproducteur',
        self::SOUS_MERES => 'Sous-mères',
        self::CHAIR => 'Jeune',
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

        // ⚠️ Avant « jeune » : « Sous-mères » et l'ancien « Lapin Sevré » sont la petite catégorie.
        if (str_contains($l, 'sous-mere') || str_contains($l, 'sous mere') || str_contains($l, 'sevre')) {
            return self::SOUS_MERES;
        }

        // « Jeune » en ÉGALITÉ STRICTE (jamais « Jeunes » ni « Jeune porc »), et les anciens libellés.
        if (str_contains($l, 'engraissement') || str_contains($l, 'chair') || $l === 'jeune') {
            return self::CHAIR;
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
