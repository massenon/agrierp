<?php

namespace App\Services;

use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Support\EffectifCategoriesJour;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;

/**
 * Ticket 15.39 — SERVICE D'EFFECTIF PAR CATÉGORIE (lapins et porcs).
 *
 * Plan « effectif automatique par catégorie » du 14/10/2026 : le serveur persiste les MOUVEMENTS
 * par catégorie et un DÉPART, et DÉRIVE `cat_eff_*` (comme `effectif_final`). Ce service n'a
 * AUCUNE interface ni push : tickets 15.40 à 15.42.
 *
 * Emplacements génériques (14.11 / 14.12) : `repro` = Reproducteur ; `sevre` = Sous-mères (lapins) /
 * Porcelet (porcs) ; `jeune` = Jeune (lapins) / Marchand (porcs) — glossaire du 17/10/2026.
 *
 * FORMULES (chaque catégorie bornée à 0 ; v = dernière fiche ANTÉRIEURE de la même bande, un jour
 * sauté est franchi ; p = passage de stade) :
 *   LAPINS  R = max(0, Rv − mR − dR)
 *           J = max(0, Jv + achat + né − mJ − dJ − p)      (achat de lapins → Jeune, D11)
 *           C = max(0, Cv − vente − mC − dC + p)           (vente → Chair)
 *   PORCS   R = max(0, Rv + achat − mR − dR)               (achat de porcs → Reproducteur, D11)
 *           P = max(0, Pv + né − mP − dP − p)
 *           M = max(0, Mv − vente − mM − dM + p)           (vente → Marchand)
 *
 * RÈGLES TRANCHÉES PAR LE CLIENT (14/10/2026) :
 *  - D3 : le passage est un TRANSFERT Jeune → Chair / Porcelet → Marchand, total inchangé ; refusé
 *    s'il dépasse la catégorie source. « Source » = la catégorie source APRÈS ses autres mouvements
 *    du jour (veille + entrées − morts − dons, bornée à 0) — interprétation de l'agent, à confirmer.
 *  - D4 : l'effectif de départ saisi est l'effectif au DÉBUT du jour de départ ; les mouvements du
 *    jour s'appliquent ensuite ; la somme des 3 catégories de départ doit égaler l'effectif total
 *    de départ, sinon refus.
 *  - D6 : à défaut de départ saisi, la dernière fiche dont les 3 `cat_eff_*` sont non nuls SERT de
 *    départ implicite — implémenté ici pour le RAPPORT À BLANC uniquement, JAMAIS écrit en base.
 *  - D8 : « somme ≠ total » est un avertissement, pas un blocage.
 *
 * ⚠️⚠️ `null` = INCONNU, propagé en null, JAMAIS lu comme 0 : une entrée inconnue rend inconnues
 * les seules catégories qu'elle touche, et l'inconnu se propage aux jours suivants. Une bande sans
 * départ saisi n'a PAS de chaîne : rien n'est calculé ni écrit (comportement antérieur inchangé).
 *
 * Les fonctions de calcul (`calculerJour`, `verifierDepart`) sont PURES : aucun accès base.
 */
class EffectifParCategorieService
{
    public const LAPINS = 'lapins';

    public const PORCS = 'porcs';

    /** Code d'espèce de la base → espèce prise en charge. */
    private const ESPECES = ['cuniculture' => self::LAPINS, 'porciculture' => self::PORCS];

    /** Mouvements ventilés « connus à zéro » d'une fiche créée par une vente sur une bande à chaîne. */
    public const MOUVEMENTS_CONNUS_A_ZERO = [
        'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 0,
        'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0,
        'passage_sevre_jeune' => 0,
    ];

    // ====================================================================== FONCTIONS PURES

    /**
     * Effectifs par catégorie d'UNE journée.
     *
     * @param  array{repro: ?int, sevre: ?int, jeune: ?int}  $veille  catégories à la veille (ou départ, D4)
     * @param  array<string, ?int>  $mouvements  achat, ne, vente, mort_repro, mort_sevre, mort_jeune,
     *                                           don_repro, don_sevre, don_jeune, passage (null = inconnu ;
     *                                           clé absente = inconnu)
     * @param  ?int  $totalFinal  effectif total de fin de journée, pour l'indicateur « somme ≠ total »
     */
    public static function calculerJour(string $espece, array $veille, array $mouvements, ?int $totalFinal = null): EffectifCategoriesJour
    {
        if (! in_array($espece, [self::LAPINS, self::PORCS], true)) {
            throw new InvalidArgumentException("Espèce non prise en charge : {$espece}.");
        }
        $lapins = $espece === self::LAPINS;
        $m = fn (string $cle): ?int => $mouvements[$cle] ?? null;
        // Ticket 15.46 — transferts entre bandes : dérivés de `livestock_transfers`, donc toujours CONNUS (absents = 0).
        $t = fn (string $cle): int => (int) ($mouvements[$cle] ?? 0);

        // Reproducteur : ne change jamais de stade (14.11). Les achats de porcs lui reviennent (D11).
        $repro = self::appliquer(
            $veille['repro'] ?? null,
            array_merge($lapins ? [] : [$m('achat')], [$t('transfert_entree_repro')]),
            [$m('mort_repro'), $m('don_repro'), $t('transfert_sortie_repro')],
        );

        // Catégorie « sevre » (Jeune / Porcelet), avant passage : les lapins achetés y entrent (D11), les nés aussi.
        $avant = self::brut(
            $veille['sevre'] ?? null,
            array_merge($lapins ? [$m('achat'), $m('ne')] : [$m('ne')], [$t('transfert_entree_sevre')]),
            [$m('mort_sevre'), $m('don_sevre'), $t('transfert_sortie_sevre')],
        );

        $passage = $m('passage');
        $refus = null;
        if ($passage === null) {
            $passageApplique = null;
        } else {
            $passageApplique = $passage;
            if ($avant !== null && $passage > max(0, $avant)) {
                $source = max(0, $avant);
                $passageApplique = $source;
                $refus = "Passage de stade refusé : {$passage} sujet(s) à faire passer, mais la catégorie source n'en compte que {$source}.";
            }
        }

        $sevre = ($avant === null || $passageApplique === null) ? null : max(0, $avant - $passageApplique);
        $jeune = self::appliquer(
            $veille['jeune'] ?? null,
            [$passageApplique, $t('transfert_entree_jeune')],
            [$m('vente'), $m('mort_jeune'), $m('don_jeune'), $t('transfert_sortie_jeune')],
        );

        $sommeDifferente = null;
        if ($repro !== null && $sevre !== null && $jeune !== null && $totalFinal !== null) {
            $sommeDifferente = ($repro + $sevre + $jeune) !== $totalFinal;
        }

        return new EffectifCategoriesJour($repro, $sevre, $jeune, $sommeDifferente, $refus, $passageApplique);
    }

    /**
     * Contrôle du départ saisi (D4) : trois catégories renseignées dont la somme égale l'effectif
     * total au début du jour de départ. Retourne le motif du refus, ou null si le départ est valide.
     *
     * @param  array{repro: ?int, sevre: ?int, jeune: ?int}  $depart
     */
    public static function verifierDepart(array $depart, ?int $totalDepart): ?string
    {
        $r = $depart['repro'] ?? null;
        $s = $depart['sevre'] ?? null;
        $j = $depart['jeune'] ?? null;

        if ($r === null || $s === null || $j === null) {
            return 'Effectif de départ incomplet : les trois catégories doivent être renseignées (0 si la catégorie est vide).';
        }
        if ($totalDepart === null) {
            return "Effectif total de départ inconnu : la somme des catégories ({$r} + {$s} + {$j}) ne peut pas être contrôlée.";
        }
        if ($r + $s + $j !== $totalDepart) {
            $somme = $r + $s + $j;

            return "La somme des catégories de départ ({$somme}) ne correspond pas à l'effectif total au début du jour de départ ({$totalDepart}).";
        }

        return null;
    }

    /** Veille + entrées − sorties, SANS plancher (null si une entrée est inconnue). */
    private static function brut(?int $base, array $plus, array $moins): ?int
    {
        if ($base === null || in_array(null, $plus, true) || in_array(null, $moins, true)) {
            return null;
        }

        return $base + array_sum($plus) - array_sum($moins);
    }

    /** Idem, borné à 0. */
    private static function appliquer(?int $base, array $plus, array $moins): ?int
    {
        $brut = self::brut($base, $plus, $moins);

        return $brut === null ? null : max(0, $brut);
    }

    // ====================================================================== ESPÈCE / CHAÎNE

    /**
     * Stade de bande → emplacement de catégorie. Lapins : Reproducteur / Sous-mères / Jeune ;
     * porcs : Reproducteur / Porcelet / Porc Marchand. `ponte` ne relève d'aucune catégorie.
     */
    private const STADE_VERS_CATEGORIE = ['reproduction' => 'repro', 'croissance' => 'sevre', 'engraissement' => 'jeune'];

    /**
     * 🔴→✅ RATIONNEMENT AUTOMATIQUE — effectif de départ DÉDUIT du stade de la bande, sans saisie.
     *
     * Le départ par catégorie devait être saisi à la main avant que la moindre ration ne se calcule :
     * tant qu'il ne l'était pas, « Rationnement & Provende Servie » restait à « — ». Une bande est créée
     * avec un stade (« Stade Initial ») : tout son effectif relève de la catégorie de ce stade, les deux
     * autres valent 0. La somme vaut donc toujours l'effectif total au début du jour (contrôle de
     * `verifierDepart` respecté). Null : espèce sans catégories ou stade sans catégorie (ponte).
     *
     * @return array{repro: int, sevre: int, jeune: int}|null
     */
    public static function departDepuisStade(LivestockLot $lot, int $totalDebutJour): ?array
    {
        $emplacement = self::STADE_VERS_CATEGORIE[$lot->stage] ?? null;

        if (self::especeDuLot($lot) === null || $emplacement === null) {
            return null;
        }

        return array_merge(['repro' => 0, 'sevre' => 0, 'jeune' => 0], [$emplacement => max(0, $totalDebutJour)]);
    }

    /** Ticket 15.46 — catégorie (repro / sevre / jeune) d'un stade de bande ; null pour `ponte` ou un stade inconnu. */
    public static function categorieDuStade(?string $stade): ?string
    {
        return self::STADE_VERS_CATEGORIE[$stade] ?? null;
    }

    public static function especeDuLot(LivestockLot $lot): ?string
    {
        return self::ESPECES[$lot->species?->code] ?? null;
    }

    /** Une bande a une chaîne exploitable si une de ses fiches porte un départ COMPLET (3 catégories). */
    public function aUneChaine(string $lotId): bool
    {
        $lot = LivestockLot::find($lotId);

        return $lot !== null
            && self::especeDuLot($lot) !== null
            && LivestockDailyEntry::where('lot_id', $lotId)
                ->whereNotNull('cat_depart_repro')->whereNotNull('cat_depart_sevre')->whereNotNull('cat_depart_jeune')
                ->exists();
    }

    /**
     * Recalcule les catégories de TOUTES les fiches de la bande à partir du départ et des
     * mouvements stockés, dans l'ordre (bande, jour). IDEMPOTENT (une fiche déjà juste n'est pas
     * réécrite : `updated_at` inchangé), TRANSACTIONNEL (tout ou rien), et ne touche JAMAIS aux
     * mouvements saisis ni à `effectif_final`.
     *
     * Une bande sans départ saisi, ou d'une autre espèce, n'a pas de chaîne : rien n'est écrit.
     * Un départ incohérent (D4) refuse la chaîne ENTIÈRE : rien n'est écrit, le motif est rendu.
     * Un passage supérieur à la source dans le STOCKÉ n'est pas bloquant (on ne casse pas une vente
     * pour une fiche voisine) : il est ramené à la source, signalé, jamais réécrit.
     *
     * @return array{chaine: bool, espece: ?string, fiches: int, modifiees: int, refus: ?string, avertissements: list<string>}
     */
    public function recalculerChaine(string $lotId): array
    {
        return DB::transaction(function () use ($lotId) {
            $lot = LivestockLot::whereKey($lotId)->lockForUpdate()->first();
            $rapport = ['chaine' => false, 'espece' => null, 'fiches' => 0, 'modifiees' => 0, 'refus' => null, 'avertissements' => []];

            if ($lot === null) {
                return $rapport;
            }

            $sim = $this->simuler($lot);
            $rapport['espece'] = $sim['espece'];
            $rapport['avertissements'] = $sim['avertissements'];

            if ($sim['mode'] !== 'explicite') {
                return $rapport;
            }

            $rapport['chaine'] = true;
            $rapport['refus'] = $sim['refus'];
            $rapport['fiches'] = count($sim['resultats']);

            if ($sim['refus'] !== null) {
                return $rapport;
            }

            foreach ($sim['fiches_calculees'] as $fiche) {
                $fiche->fill($sim['resultats'][$fiche->id]->versColonnes());
                if ($fiche->isDirty()) {
                    $fiche->save();
                    $rapport['modifiees']++;
                }
            }

            return $rapport;
        });
    }

    /**
     * Ticket 15.40 — PREMIÈRE fiche de la bande portant un départ COMPLET (la tête de la chaîne), lue en base.
     * Sert au push : le départ ne se fixe qu'une fois (D4), et une fiche antérieure à la tête n'est pas dans la chaîne.
     */
    public function teteDeChaine(string $lotId): ?LivestockDailyEntry
    {
        return LivestockDailyEntry::where('lot_id', $lotId)
            ->whereNotNull('cat_depart_repro')->whereNotNull('cat_depart_sevre')->whereNotNull('cat_depart_jeune')
            ->orderBy('entry_date')->first();
    }

    /**
     * Ticket 15.41 — ÉTAT DE LA CHAÎNE POUR UN JOUR DONNÉ (lecture seule), pour la fiche web : tout ce qu'il faut
     * pour calculer ce jour avec `calculerJour`, sans que la fiche ne recopie la moindre formule.
     *
     * Modes :
     *  - `sans_chaine`   : aucun départ complet saisi (ou espèce non prise en charge) — catégories inconnues ;
     *  - `avant_depart`  : le jour est antérieur à la tête de chaîne (D12) — catégories inconnues ;
     *  - `refus`         : le départ stocké est incohérent (D4) — catégories inconnues, `refus` porte le motif ;
     *  - `chaine`        : `veille` = les catégories de départ si le jour EST la tête (D4 : effectif au DÉBUT du
     *                      jour), sinon les `cat_eff_*` de la dernière fiche STRICTEMENT antérieure de la bande
     *                      (un jour sauté est franchi) ; une catégorie stockée à null reste inconnue.
     *
     * @return array{mode: string, depart_date: ?string, depart: ?array{repro: int, sevre: int, jeune: int}, veille: ?array{repro: ?int, sevre: ?int, jeune: ?int}, refus: ?string}
     */
    public function etatPourJour(LivestockLot $lot, string $date): array
    {
        $sortie = ['mode' => 'sans_chaine', 'depart_date' => null, 'depart' => null, 'veille' => null, 'refus' => null];

        if (self::especeDuLot($lot) === null) {
            return $sortie;
        }

        $tete = $this->teteDeChaine($lot->id);
        if ($tete === null) {
            return $sortie;
        }

        $dateTete = $tete->entry_date->format('Y-m-d');
        $depart = ['repro' => (int) $tete->cat_depart_repro, 'sevre' => (int) $tete->cat_depart_sevre, 'jeune' => (int) $tete->cat_depart_jeune];
        $sortie['depart_date'] = $dateTete;
        $sortie['depart'] = $depart;

        if ($date < $dateTete) {
            $sortie['mode'] = 'avant_depart';

            return $sortie;
        }

        // Même règle que `simuler` : total au début du jour de départ = effectif final de la fiche précédente, sinon l'effectif initial.
        $avantTete = LivestockDailyEntry::where('lot_id', $lot->id)->whereDate('entry_date', '<', $dateTete)->orderByDesc('entry_date')->first();
        $totalDepart = $avantTete !== null ? (int) $avantTete->effectif_final : (int) $lot->initial_quantity;

        $refus = self::verifierDepart($depart, $totalDepart);
        if ($refus !== null) {
            $sortie['mode'] = 'refus';
            $sortie['refus'] = $refus;

            return $sortie;
        }

        $sortie['mode'] = 'chaine';

        if ($date === $dateTete) {
            $sortie['veille'] = $depart;

            return $sortie;
        }

        $precedente = LivestockDailyEntry::where('lot_id', $lot->id)
            ->whereDate('entry_date', '<', $date)->whereDate('entry_date', '>=', $dateTete)
            ->orderByDesc('entry_date')->first();

        $sortie['veille'] = [
            'repro' => $precedente?->cat_eff_repro === null ? null : (int) $precedente->cat_eff_repro,
            'sevre' => $precedente?->cat_eff_sevre === null ? null : (int) $precedente->cat_eff_sevre,
            'jeune' => $precedente?->cat_eff_jeune === null ? null : (int) $precedente->cat_eff_jeune,
        ];

        return $sortie;
    }

    /**
     * Ticket 15.40 — D3 au moment du PUSH : le passage de stade de la fiche PROPOSÉE (non encore écrite) dépasse-t-il
     * sa catégorie source ? Simulation EN MÉMOIRE de la chaîne (départ + mouvements STOCKÉS des autres fiches, la
     * proposée à sa date), sans rien écrire et sans lire les `cat_eff_*` stockés (ils peuvent être périmés tant que la
     * cascade de fin d'envoi n'est pas passée). La source est celle APRÈS les autres mouvements du jour (lecture
     * retenue par 15.39). Rend le motif français du refus, ou null (pas de chaîne, fiche avant la tête, passage valide).
     */
    public function refusDuPassage(LivestockLot $lot, LivestockDailyEntry $proposee): ?string
    {
        $espece = self::especeDuLot($lot);
        if ($espece === null) {
            return null;
        }

        $fiches = LivestockDailyEntry::where('lot_id', $lot->id)->whereKeyNot($proposee->id)->get()
            ->push($proposee)
            ->sortBy(fn (LivestockDailyEntry $f) => $f->entry_date->format('Y-m-d'))->values();

        $indexTete = $fiches->search(fn ($f) => $f->cat_depart_repro !== null && $f->cat_depart_sevre !== null && $f->cat_depart_jeune !== null);
        if ($indexTete === false) {
            return null;
        }

        $tete = $fiches[$indexTete];
        $veille = ['repro' => (int) $tete->cat_depart_repro, 'sevre' => (int) $tete->cat_depart_sevre, 'jeune' => (int) $tete->cat_depart_jeune];

        foreach ($fiches->slice($indexTete)->values() as $f) {
            $r = self::calculerJour($espece, $veille, $f->mouvementsParCategorie());
            if ($f->id === $proposee->id) {
                return $r->refus;
            }
            $veille = ['repro' => $r->repro, 'sevre' => $r->sevre, 'jeune' => $r->jeune];
        }

        return null;
    }

    /**
     * Départ IMPLICITE (D6) : la dernière fiche dont les 3 `cat_eff_*` sont non nuls. Lecture seule.
     * Jamais écrit en base : un départ implicite n'est pas une saisie, c'est une proposition.
     *
     * @return ?array{fiche_id: string, date: string, categories: array{repro: int, sevre: int, jeune: int}, effectif_final: int, somme_differente: bool}
     */
    public function teteImplicite(string $lotId): ?array
    {
        $f = LivestockDailyEntry::where('lot_id', $lotId)
            ->whereNotNull('cat_eff_repro')->whereNotNull('cat_eff_sevre')->whereNotNull('cat_eff_jeune')
            ->orderByDesc('entry_date')->first();

        if ($f === null) {
            return null;
        }
        $cat = ['repro' => (int) $f->cat_eff_repro, 'sevre' => (int) $f->cat_eff_sevre, 'jeune' => (int) $f->cat_eff_jeune];

        return [
            'fiche_id' => $f->id,
            'date' => $f->entry_date->format('Y-m-d'),
            'categories' => $cat,
            'effectif_final' => (int) $f->effectif_final,
            'somme_differente' => array_sum($cat) !== (int) $f->effectif_final,
        ];
    }

    /**
     * RAPPORT À BLANC (lecture seule, aucune écriture) : par bande lapins/porcs, fiches, tête de
     * chaîne éventuelle, bandes sans historique. Statuts : `chaine` (départ saisi), `tete_implicite`
     * (D6, non écrite), `non_ventilee` (fiches mais aucune tête), `sans_historique` (aucune fiche).
     *
     * @return array{bandes: list<array<string, mixed>>, resume: array<string, int>}
     */
    public function rapportABlanc(): array
    {
        $lots = LivestockLot::with('species')
            ->whereHas('species', fn ($q) => $q->whereIn('code', array_keys(self::ESPECES)))
            ->orderBy('code')->get();

        $resume = ['chaine' => 0, 'tete_implicite' => 0, 'non_ventilee' => 0, 'sans_historique' => 0];
        $bandes = [];

        foreach ($lots as $lot) {
            $nb = LivestockDailyEntry::where('lot_id', $lot->id)->count();
            $ligne = [
                'lot_id' => $lot->id, 'code' => $lot->code, 'espece' => self::especeDuLot($lot), 'fiches' => $nb,
                'statut' => 'sans_historique', 'tete' => null,
                'fiches_apres_tete' => 0, 'calculables' => 0, 'a_modifier' => 0,
                'refus' => null, 'avertissements' => [],
            ];

            if ($nb > 0) {
                $sim = $this->simuler($lot, true);
                $ligne['avertissements'] = $sim['avertissements'];
                $ligne['refus'] = $sim['refus'];

                if ($sim['mode'] === 'explicite' || $sim['mode'] === 'implicite') {
                    $ligne['statut'] = $sim['mode'] === 'explicite' ? 'chaine' : 'tete_implicite';
                    $ligne['tete'] = $sim['tete'];
                    $ligne['fiches_apres_tete'] = count($sim['resultats']);
                    $ligne['calculables'] = collect($sim['resultats'])->filter(fn ($r) => $r->estComplet())->count();
                    $ligne['a_modifier'] = collect($sim['fiches_calculees'])->filter(
                        fn ($f) => isset($sim['resultats'][$f->id]) && $this->different($f, $sim['resultats'][$f->id])
                    )->count();
                } else {
                    $ligne['statut'] = 'non_ventilee';
                }
            }

            $resume[$ligne['statut']]++;
            $bandes[] = $ligne;
        }

        return ['bandes' => $bandes, 'resume' => $resume];
    }

    private function different(LivestockDailyEntry $f, EffectifCategoriesJour $r): bool
    {
        foreach ($r->versColonnes() as $colonne => $valeur) {
            $stocke = $f->{$colonne} === null ? null : (int) $f->{$colonne};
            if ($stocke !== $valeur) {
                return true;
            }
        }

        return false;
    }

    // ====================================================================== SIMULATION (sans écriture)

    /**
     * Calcule la chaîne EN MÉMOIRE. `$avecImplicite` autorise le départ implicite D6 (rapport seulement).
     *
     * @return array{mode: string, espece: ?string, tete: ?array, refus: ?string, avertissements: list<string>, fiches_calculees: Collection, resultats: array<string, EffectifCategoriesJour>}
     */
    private function simuler(LivestockLot $lot, bool $avecImplicite = false): array
    {
        $espece = self::especeDuLot($lot);
        $sortie = ['mode' => 'aucune', 'espece' => $espece, 'tete' => null, 'refus' => null, 'avertissements' => [], 'fiches_calculees' => collect(), 'resultats' => []];

        if ($espece === null) {
            return $sortie;
        }

        /** @var Collection<int, LivestockDailyEntry> $fiches */
        $fiches = LivestockDailyEntry::where('lot_id', $lot->id)->orderBy('entry_date')->get()->values();

        $indexTete = $fiches->search(fn ($f) => $f->cat_depart_repro !== null && $f->cat_depart_sevre !== null && $f->cat_depart_jeune !== null);

        if ($indexTete !== false) {
            $tete = $fiches[$indexTete];
            $depart = ['repro' => (int) $tete->cat_depart_repro, 'sevre' => (int) $tete->cat_depart_sevre, 'jeune' => (int) $tete->cat_depart_jeune];
            $totalDepart = $indexTete > 0 ? (int) $fiches[$indexTete - 1]->effectif_final : (int) $lot->initial_quantity;

            $sortie['mode'] = 'explicite';
            $sortie['tete'] = ['date' => $tete->entry_date->format('Y-m-d'), 'categories' => $depart, 'type' => 'départ saisi'];
            $sortie['refus'] = self::verifierDepart($depart, $totalDepart);
            if ($sortie['refus'] !== null) {
                return $sortie;
            }

            $veille = $depart;
            $suite = $fiches->slice($indexTete)->values();
            foreach ($suite as $i => $f) {
                if ($i > 0 && ($f->cat_depart_repro !== null || $f->cat_depart_sevre !== null || $f->cat_depart_jeune !== null)) {
                    $sortie['avertissements'][] = "Fiche du {$f->entry_date->format('d/m/Y')} : un départ y est saisi alors que la chaîne démarre déjà le {$tete->entry_date->format('d/m/Y')} ; il est ignoré.";
                }
                $veille = $this->jour($espece, $f, $veille, $sortie);
            }
            $sortie['fiches_calculees'] = $suite;

            return $sortie;
        }

        if (! $avecImplicite) {
            return $sortie;
        }

        $implicite = $this->teteImplicite($lot->id);
        if ($implicite === null) {
            return $sortie;
        }

        $sortie['mode'] = 'implicite';
        $sortie['tete'] = ['date' => $implicite['date'], 'categories' => $implicite['categories'], 'type' => 'départ implicite D6 (fin de journée)'];
        $suite = $fiches->filter(fn ($f) => $f->entry_date->format('Y-m-d') > $implicite['date'])->values();
        $veille = $implicite['categories'];
        foreach ($suite as $f) {
            $veille = $this->jour($espece, $f, $veille, $sortie);
        }
        $sortie['fiches_calculees'] = $suite;

        return $sortie;
    }

    /** Calcule une fiche, enregistre le résultat dans `$sortie`, rend les catégories de fin de journée. */
    private function jour(string $espece, LivestockDailyEntry $f, array $veille, array &$sortie): array
    {
        $r = self::calculerJour($espece, $veille, $f->mouvementsParCategorie(), (int) $f->effectif_final);

        if ($r->refus !== null) {
            $sortie['avertissements'][] = "Fiche du {$f->entry_date->format('d/m/Y')} : {$r->refus} Passage ramené à la catégorie source pour le calcul (saisie conservée).";
        }
        $sortie['resultats'][$f->id] = $r;

        return ['repro' => $r->repro, 'sevre' => $r->sevre, 'jeune' => $r->jeune];
    }
}
