<?php

namespace App\Support;

use Illuminate\Support\Collection;
use Illuminate\Support\Str;

/**
 * Ticket VOL-1 (décision client du 04/11/2026) — LES TROIS CATÉGORIES DES VOLAILLES REPRODUCTRICES.
 *
 * Même principe que les lapins (`CategorieRationLapin`) et les porcs (`CategorieRationPorc`) : l'effectif de la fiche
 * « Volailles Reproducteurs » est calculé par catégorie, et chaque catégorie porte sa ration (g/j par sujet).
 *
 * ⚠️ LIBELLÉ AFFICHÉ : « Jeune » — JAMAIS « Jeune à maturité », jamais « Poulet » (nom interne d'avant le ticket, resté
 * dans les propriétés Livewire `mortPoulet`/`donPoulet` du web et du poste pour ne rien casser). Écart ASSUMÉ avec la
 * maquette (qui dit « Poulet » aux Morts/Dons) : c'est la décision du client.
 *
 * EMPLACEMENTS GÉNÉRIQUES (colonnes de synchronisation `*_repro` / `*_sevre` / `*_jeune`, contrat /api/sync/*) :
 *   reproducteur → `repro`  : `mort_repro`, `don_repro`, `vente_repro`, `cat_depart_repro`, `cat_eff_repro`
 *   jeune        → `jeune`  : `mort_jeune`, `don_jeune`, `vente_jeune`, `cat_depart_jeune`, `cat_eff_jeune`
 *   poussin      → `sevre`  : `mort_sevre`, `don_sevre`, `vente_sevre`, `cat_depart_sevre`, `cat_eff_sevre`
 * Le passage de stade (`passage_sevre_jeune`) est le passage Poussin → Jeune. Les ACHATS vont aux Jeunes, les
 * ÉCLOSIONS (poussins nés, `ne`) aux Poussins, les VENTES à la catégorie du PRODUIT vendu (`products.categorie_effectif`).
 *
 * LA RATION se retrouve par CLÉ STABLE (libellé du barème normalisé, en ÉGALITÉ STRICTE : « reproducteur », « jeune »,
 * « poussin »), jamais par sous-chaîne : les lignes de la fiche Pondeuses (« Poussin ponte (0 à 2 mois) », « Pondeuse… »)
 * ne sont donc jamais prises pour celles-ci, et réciproquement. ⚠️ Rations PROVISOIRES (130 / 80 / 30 g/j) : valeurs à
 * confirmer avec le client, modifiables dans Paramètres Élevage.
 */
class CategorieVolaille
{
    public const REPRODUCTEUR = 'reproducteur';

    public const JEUNE = 'jeune';

    public const POUSSIN = 'poussin';

    /** Ordre d'affichage : Reproducteur, Jeune, Poussin. */
    public const CLES = [self::REPRODUCTEUR, self::JEUNE, self::POUSSIN];

    /** Libellés affichés — partout (morts, dons, ventes, départ, rationnement, stade). */
    public const LIBELLES = [
        self::REPRODUCTEUR => 'Reproducteur',
        self::JEUNE => 'Jeune',
        self::POUSSIN => 'Poussin',
    ];

    /** Clé de catégorie → emplacement générique des colonnes de synchronisation. */
    public const EMPLACEMENTS = [
        self::REPRODUCTEUR => 'repro',
        self::JEUNE => 'jeune',
        self::POUSSIN => 'sevre',
    ];

    /**
     * ⚠️ VALEURS PROVISOIRES À CONFIRMER AVEC LE CLIENT (g/j par sujet) : Reproducteur 130, Jeune 80, Poussin 30.
     * Utilisées par le semis du barème ET comme valeurs de secours si une ligne manque.
     */
    public const RATIONS_PROVISOIRES = [
        self::REPRODUCTEUR => 130,
        self::JEUNE => 80,
        self::POUSSIN => 30,
    ];

    public static function libelle(string $cle): string
    {
        return self::LIBELLES[$cle];
    }

    public static function estValide(?string $cle): bool
    {
        return $cle !== null && in_array($cle, self::CLES, true);
    }

    /** Emplacement générique (`repro` / `sevre` / `jeune`) d'une clé de catégorie, null si la clé est inconnue. */
    public static function emplacement(?string $cle): ?string
    {
        return self::EMPLACEMENTS[$cle] ?? null;
    }

    /** Clé de catégorie d'un emplacement générique. */
    public static function cleDeLEmplacement(string $emplacement): ?string
    {
        $cle = array_search($emplacement, self::EMPLACEMENTS, true);

        return $cle === false ? null : $cle;
    }

    private static function normaliser(?string $texte): string
    {
        return Str::lower(Str::ascii(trim((string) $texte)));
    }

    /**
     * Clé d'une ligne du barème par ÉGALITÉ STRICTE du libellé normalisé (casse et accents ignorés), ou null.
     * « Poussin ponte (0 à 2 mois) » ou « Pondeuse (6 à 18 mois) » ne sont PAS des catégories des reproducteurs.
     */
    public static function cleDuLibelle(?string $libelle): ?string
    {
        $l = self::normaliser($libelle);

        foreach (self::LIBELLES as $cle => $affiche) {
            if ($l === self::normaliser($affiche)) {
                return $cle;
            }
        }

        return null;
    }

    /** Vrai si la ligne du barème est une ligne des reproducteurs (et non d'un stade de pondeuse). */
    public static function estUneLigneDeReproducteurs(?string $libelle): bool
    {
        return self::cleDuLibelle($libelle) !== null;
    }

    /**
     * Ration (g/j) d'une catégorie : celle du barème si la ligne existe et est active, sinon la valeur provisoire.
     *
     * @param  Collection<int, object>  $rations  lignes de `feed_ration_standards` de l'aviculture
     */
    public static function ration(Collection $rations, string $cle): int
    {
        $ligne = $rations->first(fn ($r) => self::cleDuLibelle($r->stage_label) === $cle);

        return (int) ($ligne->ration_g_per_day ?? self::RATIONS_PROVISOIRES[$cle]);
    }

    /**
     * Catégorie d'effectif PAR DÉFAUT d'un produit de l'aviculture d'après son nom (migration et semis) : poussin d'un
     * jour → poussin ; coq / poule reproductrice / reproducteur → reproducteur ; poulet / jeune / maturité / goliath →
     * jeune. Les aliments, provendes et œufs ne sont jamais rangés. Null = pas de règle sûre (jamais rangé au hasard).
     */
    public static function devinerDepuisLeNom(?string $nom): ?string
    {
        $n = self::normaliser($nom);

        if ($n === '' || preg_match('/aliment|provende|oeuf|sac\b|plateau|medicament|vaccin/', $n) === 1) {
            return null;
        }
        if (str_contains($n, 'poussin')) {
            return self::POUSSIN;
        }
        if (str_contains($n, 'reproducteur') || preg_match('/\bcoqs?\b|\bpoules?\b/', $n) === 1) {
            return self::REPRODUCTEUR;
        }
        if (str_contains($n, 'poulet') || str_contains($n, 'jeune') || str_contains($n, 'maturite') || str_contains($n, 'goliath')) {
            return self::JEUNE;
        }

        return null;
    }

    /**
     * Ticket VOL-1 — TABLEAU DE RATIONNEMENT de la fiche « Volailles Reproducteurs » : effectif CALCULÉ de chaque
     * catégorie × la ration de sa ligne du barème. Lignes dans l'ordre Reproducteur, Jeune, Poussin. Même règle, mêmes
     * arrondis que le poste (`ration_reproducteurs.dart`, parité exécutée).
     *
     * @param  Collection<int, object>  $rations  lignes de `feed_ration_standards` de l'aviculture
     * @param  array{repro: ?int, sevre: ?int, jeune: ?int}  $effectifs  par emplacement ; null = indisponible (jamais lu 0)
     * @return array{lignes: list<array{cle: string, libelle: string, ration: int, effectif: ?int, total_g: ?int}>, total_g: ?int, total_kg: ?float}
     */
    public static function tableauReproducteurs(Collection $rations, array $effectifs): array
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
