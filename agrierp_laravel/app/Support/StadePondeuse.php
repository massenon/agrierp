<?php

namespace App\Support;

use Illuminate\Support\Collection;
use Illuminate\Support\Str;

/**
 * Ticket VOL-2 (décision client du 05/11/2026) — LES QUATRE STADES DES VOLAILLES PONDEUSES.
 *
 * Même principe que les volailles reproductrices (`CategorieVolaille`, VOL-1), les lapins et les porcs : l'effectif de la
 * fiche « Pondeuses » est calculé par stade, et chaque stade porte sa ration (g/j par sujet).
 *
 * LIBELLÉS = ceux, EXACTS, des quatre lignes du barème de l'aviculture (`FeedRationStandardsSeeder`) : on ne les renomme
 * pas. Ils s'affichent tels quels partout (morts, dons, ventes, départ, passages, rationnement), au web ET au poste.
 *
 * EMPLACEMENTS GÉNÉRIQUES de synchronisation (le contrat `/api/sync/*` ne casse aucun nom de clé existant : on AJOUTE des
 * colonnes) :
 *   pondeuse           → `repro`  : `mort_repro`, `don_repro`, `vente_repro`, `cat_depart_repro`, `cat_eff_repro`
 *   poulette           → `jeune`  : `mort_jeune`, `don_jeune`, `vente_jeune`, `cat_depart_jeune`, `cat_eff_jeune`
 *   poussin en croiss. → `sevre`  : `mort_sevre`, `don_sevre`, `vente_sevre`, `cat_depart_sevre`, `cat_eff_sevre`
 *   poussin ponte      → `quatre` : `mort_4`, `don_4`, `vente_4`, `cat_depart_4`, `cat_eff_4` (colonne qui existait déjà, sans usage)
 * Passages (transferts de stade, total inchangé) :
 *   Poussin ponte → Poussin en croissance : `passage_4_sevre`     (NOUVEAU)
 *   Poussin en croissance → Poulette      : `passage_sevre_jeune` (le même sens que chez les reproducteurs : sevre → jeune)
 *   Poulette → Pondeuse                   : `passage_jeune_repro` (NOUVEAU)
 * Les ACHATS vont à Poulette (le jeune à maturité), les ÉCLOSIONS à Poussin ponte, les VENTES au stade du PRODUIT vendu
 * (`products.categorie_effectif`).
 *
 * LA RATION se retrouve par CLÉ STABLE : libellé du barème normalisé (casse, accents ET tranche d'âge entre parenthèses
 * ignorés), en ÉGALITÉ STRICTE — « poussin ponte », « poussin en croissance », « poulette », « pondeuse ». Jamais par
 * sous-chaîne : « Poussin » (VOL-1) n'est pas « Poussin ponte », et « Reproducteur » / « Jeune » ne sont jamais des stades
 * de pondeuse.
 */
class StadePondeuse
{
    public const POUSSIN_PONTE = 'poussin_ponte';

    public const POUSSIN_CROISSANCE = 'poussin_croissance';

    public const POULETTE = 'poulette';

    public const PONDEUSE = 'pondeuse';

    /** Ordre de la chaîne ET de l'affichage : Poussin ponte, Poussin en croissance, Poulette, Pondeuse. */
    public const CLES = [self::POUSSIN_PONTE, self::POUSSIN_CROISSANCE, self::POULETTE, self::PONDEUSE];

    /** Libellés affichés = libellés EXACTS du barème (`FeedRationStandardsSeeder`). */
    public const LIBELLES = [
        self::POUSSIN_PONTE => 'Poussin ponte (0 à 2 mois)',
        self::POUSSIN_CROISSANCE => 'Poussin en croissance (2 à 4 mois)',
        self::POULETTE => 'Poulette (4 à 5.5 mois)',
        self::PONDEUSE => 'Pondeuse (6 à 18 mois)',
    ];

    /** Clé de stade → emplacement générique. */
    public const EMPLACEMENTS = [
        self::PONDEUSE => 'repro',
        self::POULETTE => 'jeune',
        self::POUSSIN_CROISSANCE => 'sevre',
        self::POUSSIN_PONTE => 'quatre',
    ];

    /** Valeurs du barème d'origine (g/j), utilisées comme valeurs de secours si une ligne manque. */
    public const RATIONS_PAR_DEFAUT = [
        self::POUSSIN_PONTE => 30,
        self::POUSSIN_CROISSANCE => 60,
        self::POULETTE => 80,
        self::PONDEUSE => 110,
    ];

    public static function libelle(string $cle): string
    {
        return self::LIBELLES[$cle];
    }

    public static function estValide(?string $cle): bool
    {
        return $cle !== null && in_array($cle, self::CLES, true);
    }

    /** Emplacement générique (`repro` / `jeune` / `sevre` / `quatre`) d'un stade, null si la clé est inconnue. */
    public static function emplacement(?string $cle): ?string
    {
        return self::EMPLACEMENTS[$cle] ?? null;
    }

    public static function cleDeLEmplacement(string $emplacement): ?string
    {
        $cle = array_search($emplacement, self::EMPLACEMENTS, true);

        return $cle === false ? null : $cle;
    }

    /** Libellé du stade d'un emplacement générique. */
    public static function libelleDeLEmplacement(string $emplacement): string
    {
        return self::LIBELLES[self::cleDeLEmplacement($emplacement)];
    }

    /** Clé de comparaison : minuscules, sans accent, SANS la tranche d'âge entre parenthèses, espaces réduits. */
    private static function normaliser(?string $texte): string
    {
        $sansAge = preg_replace('/\([^)]*\)/u', ' ', (string) $texte);

        return trim(preg_replace('/\s+/u', ' ', Str::lower(Str::ascii($sansAge))));
    }

    /** Clé de stade d'une ligne du barème par ÉGALITÉ STRICTE du libellé normalisé, ou null. */
    public static function cleDuLibelle(?string $libelle): ?string
    {
        $l = self::normaliser($libelle);

        foreach (self::CLES as $cle) {
            if ($l === self::normaliser(self::LIBELLES[$cle])) {
                return $cle;
            }
        }

        return null;
    }

    /** Ration (g/j) d'un stade : celle du barème si la ligne existe, sinon la valeur d'origine. */
    public static function ration(Collection $rations, string $cle): int
    {
        $ligne = $rations->first(fn ($r) => self::cleDuLibelle($r->stage_label) === $cle);

        return (int) ($ligne->ration_g_per_day ?? self::RATIONS_PAR_DEFAUT[$cle]);
    }

    /**
     * Stade PAR DÉFAUT d'un produit de l'aviculture d'après son nom (migration et semis), pour les produits de la fiche
     * Pondeuses : poussin d'un jour « ponte » → poussin ponte ; poussin en croissance → idem ; poulette → poulette ;
     * pondeuse / poule de réforme → pondeuse. Null = pas de règle sûre (jamais rangé au hasard).
     */
    public static function devinerDepuisLeNom(?string $nom): ?string
    {
        $n = Str::lower(Str::ascii(trim((string) $nom)));

        if ($n === '' || preg_match('/aliment|provende|oeuf|sac\b|plateau|medicament|vaccin/', $n) === 1) {
            return null;
        }
        if (str_contains($n, 'poulette')) {
            return self::POULETTE;
        }
        if (str_contains($n, 'pondeuse') || str_contains($n, 'reforme')) {
            return self::PONDEUSE;
        }
        if (str_contains($n, 'poussin') && str_contains($n, 'croissance')) {
            return self::POUSSIN_CROISSANCE;
        }
        if (str_contains($n, 'poussin') && str_contains($n, 'ponte')) {
            return self::POUSSIN_PONTE;
        }

        return null;
    }

    /**
     * TABLEAU DE RATIONNEMENT de la fiche « Pondeuses » : effectif CALCULÉ de chaque stade × la ration de sa ligne du
     * barème. Lignes dans l'ordre de la chaîne. Même règle, mêmes arrondis que le poste (`ration_pondeuses.dart`).
     *
     * @param  Collection<int, object>  $rations  lignes de `feed_ration_standards` de l'aviculture
     * @param  array<string, ?int>  $effectifs  par emplacement (`repro`, `sevre`, `jeune`, `quatre`) ; null = indisponible
     * @return array{lignes: list<array{cle: string, libelle: string, ration: int, effectif: ?int, total_g: ?int}>, total_g: ?int, total_kg: ?float}
     */
    public static function tableau(Collection $rations, array $effectifs): array
    {
        $lignes = [];
        foreach (self::CLES as $cle) {
            $effectif = $effectifs[self::EMPLACEMENTS[$cle]] ?? null;
            $ration = self::ration($rations, $cle);
            $lignes[] = [
                'cle' => $cle,
                'libelle' => self::LIBELLES[$cle],
                'ration' => $ration,
                'effectif' => $effectif === null ? null : (int) $effectif,
                'total_g' => $effectif === null ? null : (int) $effectif * $ration,
            ];
        }

        $inconnu = in_array(null, array_column($lignes, 'total_g'), true);
        $total = $inconnu ? null : array_sum(array_column($lignes, 'total_g'));

        return [
            'lignes' => $lignes,
            'total_g' => $total,
            'total_kg' => $total === null ? null : round($total / 1000, 2),
        ];
    }
}
