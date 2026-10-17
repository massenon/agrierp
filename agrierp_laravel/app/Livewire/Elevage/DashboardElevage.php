<?php

namespace App\Livewire\Elevage;

use App\Models\InfirmaryRecord;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\VeterinaryRecord;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 3.13 (Sprint 3) — elevage-dashboard.html → Livewire\Elevage\DashboardElevage
 * Page mère à 5 onglets internes (Document 05 §Module 2).
 *
 * GMQ (g/j) = (Poids Final − Poids Initial) ÷ Nombre de Jours entre les
 * deux pesées — vérifiée contre DEUX sources concordantes
 * (FORMULE_FICHE_ELEVAGE.md §5 et 05_MODULE_SPECIFICATIONS.md §GMQ &
 * Croissance), calculée à partir des pesées déjà saisies dans les fiches
 * journalières (`livestock_daily_entries.weight_sample_avg_g`, tickets
 * 3.5-3.8). Aucun calcul JS live dans le prototype pour cette formule
 * (contrairement aux 4 précédentes) — implémentation Laravel réelle
 * directement, comme demandé par le document de référence.
 *
 * ⚠️ PÉRIMÈTRE ANNONCÉ AVANT CODAGE :
 * - "Bilan Technico-Économique" (onglet interne) : 🔴→✅ LIVRÉ AU TICKET
 *   14.44. Les deux dépendances citées existent depuis (achats au Sprint
 *   5, centres de coût au Sprint 10), et les revenus par bande depuis le
 *   ticket 14.44 lui-même. Le prototype affiche dans cet onglet exactement
 *   l'écran `bilan-technico-economique.html` : le composant Livewire
 *   correspondant y est donc IMBRIQUÉ tel quel, jamais recopié — un second
 *   calcul du coût de revient aurait fini par diverger du premier, et la
 *   ferme aurait lu deux chiffres différents pour la même bande.
 * - Graphique SVG "Croissance (GMQ) par Espèce" du prototype remplacé par
 *   un tableau réel — aucune librairie de graphiques disponible côté Blade
 *   à ce stade du projet (simplification documentée, pas un graphique
 *   fictif avec des points inventés).
 * - "Rappels VMS à venir" renvoie vers le calendrier réel déjà construit
 *   (ticket 3.11), jamais une liste dupliquée localement.
 */
#[Layout('layouts.app')]
class DashboardElevage extends Component
{
    #[Url]
    public string $tab = 'synthese';

    public function getActiveLotsProperty()
    {
        return LivestockLot::with('species')->where('status', 'actif')->where('is_active', true)->get();
    }

    public function getSyntheseKpisProperty(): array
    {
        $lots = $this->activeLots;
        $lotIds = $lots->pluck('id');

        $last7Days = LivestockDailyEntry::whereIn('lot_id', $lotIds)
            ->whereBetween('entry_date', [now()->subDays(6), now()])
            ->get();

        $totalMorts = $last7Days->sum('mort');
        $totalEffectifDepart = $last7Days->sum(fn ($e) => $e->previousEffectif());

        return [
            'effectif_total' => (int) $lots->sum('current_quantity'),
            'gmq_moyen' => $this->consolidatedGmq(),
            'taux_mortalite_7j' => $totalEffectifDepart > 0 ? round(($totalMorts / $totalEffectifDepart) * 100, 1) : 0.0,
        ];
    }

    public function getSpeciesSummaryProperty()
    {
        return LivestockSpecies::enabled()->get()->map(function ($species) {
            $lots = $this->activeLots->where('species_id', $species->id);
            $lotIds = $lots->pluck('id');
            $monthEntries = LivestockDailyEntry::whereIn('lot_id', $lotIds)
                ->whereBetween('entry_date', [now()->startOfMonth(), now()->endOfMonth()])
                ->get();

            $totalMorts = $monthEntries->sum('mort');
            $totalEffectifDepart = $monthEntries->sum(fn ($e) => $e->previousEffectif());

            return [
                'species' => $species,
                'effectif' => (int) $lots->sum('current_quantity'),
                'taux_mortalite' => $totalEffectifDepart > 0 ? round(($totalMorts / $totalEffectifDepart) * 100, 1) : 0.0,
            ];
        });
    }

    private function consolidatedGmq(): ?float
    {
        $values = $this->activeLots->map(fn ($lot) => $this->gmqForLot($lot))->filter(fn ($v) => $v !== null);

        return $values->isNotEmpty() ? round($values->avg(), 1) : null;
    }

    /**
     * 🔴→✅ TICKET 14.9 — délégué à `GrowthAnalysisService`. Ce composant
     * portait DEUX implémentations de la même formule (`gmqForLot()` et
     * `getGmqTableProperty()`), qui auraient pu diverger à la première
     * correction appliquée à une seule des deux. Le calcul vit désormais en
     * un seul endroit, partagé avec `AnalyseCroissance` (ticket 14.9).
     * La formule retenue ici reste inchangée : GMQ CUMULÉ depuis la première
     * pesée du lot — voir le docblock du service pour l'écart assumé avec la
     * formule « deux dernières pesées » d'`analyse-croissance.html`.
     */
    private function gmqForLot(LivestockLot $lot): ?float
    {
        return app(\App\Services\GrowthAnalysisService::class)->gmqCumule($lot->id);
    }

    public function getGmqTableProperty()
    {
        return $this->activeLots->map(function ($lot) {
            $weighIns = LivestockDailyEntry::where('lot_id', $lot->id)
                ->whereNotNull('weight_sample_avg_g')
                ->orderBy('entry_date')
                ->get(['entry_date', 'weight_sample_avg_g']);

            if ($weighIns->count() < 2) {
                return [
                    'lot' => $lot,
                    'poids_initial' => $weighIns->first()?->weight_sample_avg_g,
                    'poids_actuel' => $weighIns->last()?->weight_sample_avg_g,
                    'jours' => null,
                    'gmq' => null,
                ];
            }

            $first = $weighIns->first();
            $last = $weighIns->last();
            $days = $first->entry_date->diffInDays($last->entry_date);

            return [
                'lot' => $lot,
                'poids_initial' => $first->weight_sample_avg_g,
                'poids_actuel' => $last->weight_sample_avg_g,
                'jours' => $days,
                'gmq' => $days > 0 ? round(($last->weight_sample_avg_g - $first->weight_sample_avg_g) / $days, 1) : null,
            ];
        });
    }

    public function getSanitaireBySpeciesProperty()
    {
        return LivestockSpecies::enabled()->get()->map(function ($species) {
            $lotIds = LivestockLot::where('species_id', $species->id)->pluck('id');

            $records = VeterinaryRecord::whereIn('lot_id', $lotIds)
                ->whereMonth('record_date', now()->month)->whereYear('record_date', now()->year);

            $effectifTotal = (int) LivestockLot::whereIn('id', $lotIds)->where('status', 'actif')->sum('current_quantity');
            $enInfirmerie = InfirmaryRecord::whereIn('lot_id', $lotIds)->where('status', 'en_cours')->count();

            return [
                'species' => $species,
                'nb_traitements' => (clone $records)->count(),
                'cout_total' => (float) (clone $records)->sum('cost'),
                'taux_morbidite' => $effectifTotal > 0 ? round(($enInfirmerie / $effectifTotal) * 100, 1) : 0.0,
            ];
        });
    }

    public function getSanitaireKpisProperty(): array
    {
        $lotIds = $this->activeLots->pluck('id');
        $records = VeterinaryRecord::whereIn('lot_id', $lotIds)
            ->whereMonth('record_date', now()->month)->whereYear('record_date', now()->year);

        $traitementFrequent = (clone $records)->select('action_type')
            ->groupBy('action_type')
            ->selectRaw('action_type, COUNT(*) as total')
            ->orderByDesc('total')
            ->first();

        return [
            'nb_traitements_mois' => (clone $records)->count(),
            'cout_sanitaire_mois' => (float) (clone $records)->sum('cost'),
            'traitement_frequent' => $traitementFrequent?->action_type,
        ];
    }

    public function getPrevisionsProperty()
    {
        return $this->activeLots->map(function ($lot) {
            $weighIns = LivestockDailyEntry::where('lot_id', $lot->id)
                ->whereNotNull('weight_sample_avg_g')
                ->orderBy('entry_date')
                ->get(['entry_date', 'weight_sample_avg_g']);

            if ($weighIns->count() < 3) {
                return ['lot' => $lot, 'insufficient' => true];
            }

            $x0 = $weighIns->first()->entry_date;
            $points = $weighIns->map(fn ($e) => [
                'x' => $x0->diffInDays($e->entry_date),
                'y' => (float) $e->weight_sample_avg_g,
            ]);

            $n = $points->count();
            $sumX = $points->sum('x');
            $sumY = $points->sum('y');
            $sumXY = $points->sum(fn ($p) => $p['x'] * $p['y']);
            $sumX2 = $points->sum(fn ($p) => $p['x'] ** 2);

            $denominator = ($n * $sumX2) - ($sumX ** 2);

            if ($denominator == 0) {
                return ['lot' => $lot, 'insufficient' => true];
            }

            $slope = (($n * $sumXY) - ($sumX * $sumY)) / $denominator;
            $intercept = ($sumY - ($slope * $sumX)) / $n;

            $lastX = $points->last()['x'];
            $projection30j = round($intercept + $slope * ($lastX + 30));

            return [
                'lot' => $lot,
                'insufficient' => false,
                'poids_actuel' => (int) $weighIns->last()->weight_sample_avg_g,
                'tendance_g_par_jour' => round($slope, 1),
                'projection_30j' => $projection30j,
            ];
        });
    }

    public function render()
    {
        return view('livewire.elevage.dashboard-elevage', ['title' => 'Élevage > Dashboard Élevage']);
    }
}
