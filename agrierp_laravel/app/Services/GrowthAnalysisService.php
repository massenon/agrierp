<?php

namespace App\Services;

use App\Models\GrowthStandard;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;

/**
 * Ticket 14.9 (Sprint 14) — calcul du GMQ (Gain Moyen Quotidien), extrait ici
 * comme point de vérité unique.
 *
 * ⚠️ DEUX FORMULES RÉELLEMENT DIFFÉRENTES, TOUTES DEUX NOMMÉES « GMQ » À
 * L'ÉCRAN — écart trouvé en construisant cet écran, signalé plutôt
 * qu'harmonisé unilatéralement :
 *
 *   • `gmqCumule()`  — (dernière pesée − PREMIÈRE pesée) ÷ jours écoulés.
 *     C'est ce que calcule `DashboardElevage` (ticket 3.13) : la croissance
 *     moyenne depuis le début du lot.
 *   • `gmqRecent()`  — (dernière pesée − AVANT-DERNIÈRE) ÷ jours écoulés.
 *     C'est la définition écrite noir sur blanc dans `analyse-croissance.html`
 *     (« Poids actuel − Poids précédent », colonnes « Poids Précédent /
 *     Poids Actuel / Jours Écoulés »).
 *
 * Les deux sont légitimes et répondent à des questions différentes
 * (performance globale du lot vs dynamique la plus récente), mais afficher
 * les deux sous le même nom sur deux écrans peut dérouter. **Chaque écran
 * conserve la formule que sa propre spécification impose**, et le libellé
 * précise laquelle est utilisée. À arbitrer avec la Direction si un seul
 * indicateur doit subsister.
 *
 * Ce service supprime au passage une duplication interne réelle :
 * `DashboardElevage` calculait la même chose deux fois
 * (`gmqForLot()` et `getGmqTableProperty()`).
 */
class GrowthAnalysisService
{
    /** Pesées réelles d'un lot, chronologiques — jusqu'à `$jusquau` inclus (Y-m-d) s'il est donné. */
    private function weighIns(string $lotId, ?string $jusquau = null)
    {
        return LivestockDailyEntry::where('lot_id', $lotId)
            ->whereNotNull('weight_sample_avg_g')
            ->when($jusquau, fn ($q) => $q->whereDate('entry_date', '<=', $jusquau))
            ->orderBy('entry_date')
            ->get(['entry_date', 'weight_sample_avg_g']);
    }

    /**
     * GMQ depuis la première pesée du lot — formule de `DashboardElevage`.
     *
     * Ticket H11 — `$jusquau` (Y-m-d) donne le GMQ cumulé TEL QU'IL ÉTAIT CONNU à cette date : les courbes
     * hebdomadaires du poste (`_serieHebdomadaire`, pesées `entry_date <= borne`) en sont faites, sur la même formule.
     */
    public function gmqCumule(string $lotId, ?string $jusquau = null): ?float
    {
        $pesees = $this->weighIns($lotId, $jusquau);

        if ($pesees->count() < 2) {
            return null;
        }

        return $this->gmqEntre($pesees->first(), $pesees->last());
    }

    /**
     * GMQ entre les DEUX DERNIÈRES pesées — formule d'`analyse-croissance.html`.
     *
     * @return array{poids_precedent: int, poids_actuel: int, jours: int, gmq: float}|null
     */
    public function gmqRecent(string $lotId): ?array
    {
        $pesees = $this->weighIns($lotId);

        if ($pesees->count() < 2) {
            return null;
        }

        $avant = $pesees[$pesees->count() - 2];
        $actuel = $pesees->last();
        $gmq = $this->gmqEntre($avant, $actuel);

        if ($gmq === null) {
            return null;
        }

        return [
            'poids_precedent' => (int) $avant->weight_sample_avg_g,
            'poids_actuel' => (int) $actuel->weight_sample_avg_g,
            'date_pesee' => $actuel->entry_date->format('Y-m-d'),
            'jours' => (int) $avant->entry_date->diffInDays($actuel->entry_date),
            'gmq' => $gmq,
        ];
    }

    private function gmqEntre($debut, $fin): ?float
    {
        $jours = $debut->entry_date->diffInDays($fin->entry_date);

        // Deux pesées le même jour ne définissent aucun gain QUOTIDIEN :
        // renvoyer une division par zéro déguisée serait pire que rien.
        if ($jours <= 0) {
            return null;
        }

        return round(($fin->weight_sample_avg_g - $debut->weight_sample_avg_g) / $jours, 1);
    }

    /**
     * Lignes d'analyse pour tous les lots actifs — un lot sans au moins deux
     * pesées est EXCLU (le prototype titre lui-même son KPI « Lots Suivis
     * (Pesées ≥ 2) »), jamais affiché avec un GMQ nul trompeur.
     *
     * @return array<int, array<string, mixed>>
     */
    public function rows(?string $speciesCode = null): array
    {
        $lots = LivestockLot::with('species')
            ->where('status', 'actif')
            ->where('is_active', true)
            ->when($speciesCode, fn ($q) => $q->whereHas('species', fn ($s) => $s->where('code', $speciesCode)))
            ->orderBy('code')
            ->get();

        $standards = GrowthStandard::all();

        $rows = [];

        foreach ($lots as $lot) {
            $recent = $this->gmqRecent($lot->id);

            if ($recent === null) {
                continue;
            }

            $standard = $standards->first(fn ($s) => $s->species_code === $lot->species?->code
                && $s->stage_label === $lot->stage);

            $rows[] = array_merge($recent, [
                'lot_code' => $lot->code,
                'species_label' => $lot->species?->label ?? '—',
                'species_code' => $lot->species?->code,
                'stage' => $lot->stage,
                'objectif_min' => $standard?->gmq_min_g_per_day,
                'objectif_max' => $standard?->gmq_max_g_per_day,
                'statut' => $this->statut($recent['gmq'], $standard),
            ]);
        }

        return $rows;
    }

    /**
     * Sans barème pour l'espèce/stade, le statut est « non défini » — jamais
     * « dans la cible » par défaut, ce qui laisserait croire à une conformité
     * jamais vérifiée.
     */
    private function statut(float $gmq, ?GrowthStandard $standard): string
    {
        if (! $standard) {
            return 'non_defini';
        }

        if ($gmq < $standard->gmq_min_g_per_day) {
            return 'sous_objectif';
        }

        if ($gmq > $standard->gmq_max_g_per_day) {
            return 'au_dessus';
        }

        return 'dans_cible';
    }

    /**
     * Ticket U2 (décision client D-U2 du 19/10/2026 : « une seule source, la table `growth_standards` ») —
     * OBJECTIF DE GMQ D'UNE ESPÈCE pour un ensemble de bandes (carte « GMQ Moyen … » du Dashboard Élevage, cartes
     * par espèce d'Analyse des Croissances, et `DashboardElevageRepository.objectifPour` du poste, identique).
     *
     * Règle : chaque bande prend le barème de SON stade, exactement comme `rows()` (`species_code` ET
     * `stage_label === $lot->stage`, égalité stricte) ; l'objectif de l'espèce est l'ENVELOPPE des barèmes ainsi
     * trouvés — plus petit des minima, plus grand des maxima. Une bande dont le stade n'a pas de barème n'apporte
     * rien. Aucun barème trouvé → `null` (« — » à l'écran), jamais 0 et jamais un barème d'un autre stade :
     * l'enveloppe de toute l'espèce mêlerait la croissance des truies (40-80 g/j) à l'engraissement (500-650 g/j),
     * et « Objectif non défini » d'Analyse des Croissances deviendrait, sur le tableau de bord, un objectif inventé.
     *
     * @param  iterable<GrowthStandard|array>  $standards  barèmes (`species_code`, `stage_label`, `gmq_min_g_per_day`, `gmq_max_g_per_day`)
     * @param  iterable<?string>  $stades  stades des bandes moyennées par la carte
     * @return array{0: int, 1: int}|null [minimum, maximum] en g/jour
     */
    public static function objectifPour(iterable $standards, string $codeEspece, iterable $stades): ?array
    {
        $stades = collect($stades)->filter(fn ($s) => $s !== null)->unique()->values()->all();
        $min = null;
        $max = null;

        foreach ($standards as $s) {
            $s = is_array($s) ? (object) $s : $s;
            if ($s->species_code !== $codeEspece || ! in_array($s->stage_label, $stades, true)) {
                continue;
            }
            $min = $min === null ? (int) $s->gmq_min_g_per_day : min($min, (int) $s->gmq_min_g_per_day);
            $max = $max === null ? (int) $s->gmq_max_g_per_day : max($max, (int) $s->gmq_max_g_per_day);
        }

        return $min === null ? null : [$min, $max];
    }

    /**
     * Moyennes par espèce, pour les cartes KPI — calculées sur les lots
     * réellement suivis, jamais sur une constante.
     *
     * Ticket U2 — l'objectif de la carte est `objectifPour()` sur les stades des lots moyennés. Il était celui du
     * DERNIER lot lu de l'espèce : un lot sans barème lu en dernier effaçait l'objectif des autres.
     *
     * @return array<string, array{label: string, gmq: ?float, objectif_min: ?int, objectif_max: ?int, nb_lots: int}>
     */
    public function averagesBySpecies(): array
    {
        $rows = $this->rows();
        $standards = GrowthStandard::all();
        $parEspece = [];

        foreach ($rows as $row) {
            $code = $row['species_code'] ?? '—';
            $parEspece[$code]['label'] = $row['species_label'];
            $parEspece[$code]['gmqs'][] = $row['gmq'];
            $parEspece[$code]['stades'][] = $row['stage'];
        }

        $moyennes = [];
        foreach ($parEspece as $code => $e) {
            $objectif = self::objectifPour($standards, (string) $code, $e['stades']);
            $moyennes[$code] = [
                'label' => $e['label'],
                'gmq' => round(array_sum($e['gmqs']) / count($e['gmqs']), 1),
                'objectif_min' => $objectif[0] ?? null,
                'objectif_max' => $objectif[1] ?? null,
                'nb_lots' => count($e['gmqs']),
            ];
        }

        return $moyennes;
    }

    /** Nombre de lots réellement suivis (au moins 2 pesées). */
    public function trackedLotCount(): int
    {
        return count($this->rows());
    }
}
