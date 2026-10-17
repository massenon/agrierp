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
    /** Pesées réelles d'un lot, chronologiques. */
    private function weighIns(string $lotId)
    {
        return LivestockDailyEntry::where('lot_id', $lotId)
            ->whereNotNull('weight_sample_avg_g')
            ->orderBy('entry_date')
            ->get(['entry_date', 'weight_sample_avg_g']);
    }

    /** GMQ depuis la première pesée du lot — formule de `DashboardElevage`. */
    public function gmqCumule(string $lotId): ?float
    {
        $pesees = $this->weighIns($lotId);

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
     * Moyennes par espèce, pour les cartes KPI — calculées sur les lots
     * réellement suivis, jamais sur une constante.
     *
     * @return array<string, array{label: string, gmq: ?float, objectif_min: ?int, objectif_max: ?int, nb_lots: int}>
     */
    public function averagesBySpecies(): array
    {
        $rows = $this->rows();
        $parEspece = [];

        foreach ($rows as $row) {
            $code = $row['species_code'] ?? '—';
            $parEspece[$code]['label'] = $row['species_label'];
            $parEspece[$code]['gmqs'][] = $row['gmq'];
            $parEspece[$code]['objectif_min'] = $row['objectif_min'];
            $parEspece[$code]['objectif_max'] = $row['objectif_max'];
        }

        return array_map(fn ($e) => [
            'label' => $e['label'],
            'gmq' => round(array_sum($e['gmqs']) / count($e['gmqs']), 1),
            'objectif_min' => $e['objectif_min'],
            'objectif_max' => $e['objectif_max'],
            'nb_lots' => count($e['gmqs']),
        ], $parEspece);
    }

    /** Nombre de lots réellement suivis (au moins 2 pesées). */
    public function trackedLotCount(): int
    {
        return count($this->rows());
    }
}
