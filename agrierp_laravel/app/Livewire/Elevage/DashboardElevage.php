<?php

namespace App\Livewire\Elevage;

use App\Models\GrowthStandard;
use App\Models\InfirmaryRecord;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\VeterinaryRecord;
use App\Models\VeterinaryWithdrawalPeriod;
use App\Services\GrowthAnalysisService;
use App\Services\ProtocoleDuJourService;
use Illuminate\Support\Collection;
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
 *
 * ⚠️ TICKET H11 (décision client D-H-maquette du 19/10/2026) — LES AJOUTS DU POSTE SONT CONSTRUITS ICI, pour que les
 * deux surfaces soient identiques. Référence : `agrierp_flutter/lib/features/elevage/dashboard_elevage_repository.dart`
 * et `dashboard_elevage_screen.dart`, formules et libellés repris tels quels :
 * - courbe SVG « Croissance (GMQ) par Espèce » (GMQ cumulé connu à 5 bornes hebdomadaires) ;
 * - 4ᵉ ligne propre à chaque carte de filière (Mères / Géniteurs, Taux de ponte, Truies reproductrices, Taux d'éclosion) ;
 * - liste CALCULÉE des rappels VMS (moteur unique `ProtocoleDuJourService`, 7 jours, + rémanences en cours), AU-DESSUS du
 *   texte et du lien d'origine, qui restent ;
 * - onglet GMQ : filtre d'espèce (tableau seulement, comme au poste), 4 cartes, courbe 8 semaines de la bande suivie ;
 * - onglet Prévision : sélecteur de bande, horizons 7/14/30/60, 3 cartes, tableau Échéance / Poids — même régression
 *   que le tableau du Blade.
 * La note « 2026 vs 2025 » de l'onglet sanitaire du poste n'est PAS reprise : elle explique une limite du TIRAGE du
 * poste (l'historique de l'an dernier ne descend pas), qui n'existe pas au web — la recopier y serait faux.
 */
#[Layout('layouts.app')]
class DashboardElevage extends Component
{
    #[Url]
    public string $tab = 'synthese';

    /** Ticket H11 — filtre d'espèce de l'onglet GMQ (« all » au poste). */
    public string $espece = 'all';

    /** Ticket H11 — bande retenue par le sélecteur de l'onglet Prévision (`null` : la première projetable). */
    public ?string $bandePrevision = null;

    /** Ticket H11 — horizon de projection, en jours (14 par défaut au poste). */
    public int $horizon = 14;

    /** Horizons proposés par le poste (`horizons`), en jours. */
    public const HORIZONS = [7, 14, 30, 60];

    /**
     * Espèces des trois cartes « GMQ Moyen … » de l'onglet GMQ, dans leur ordre.
     *
     * Ticket U2 (décision client D-U2 du 19/10/2026) — les OBJECTIFS ne sont plus des constantes (ils recopiaient
     * `DashboardElevageRepository.objectifs` du poste, lui-même en dur) : ils viennent de `growth_standards`, par
     * `GrowthAnalysisService::objectifPour()` (voir `getGmqCartesProperty`).
     */
    public const ESPECES_CARTES_GMQ = ['cuniculture', 'aviculture', 'porciculture'];

    /** Horizon des rappels VMS, en jours (`horizonRappels` du poste). */
    public const HORIZON_RAPPELS = 7;

    public function getActiveLotsProperty()
    {
        return LivestockLot::with('species')->where('status', 'actif')->where('is_active', true)->get();
    }

    public function getSyntheseKpisProperty(): array
    {
        $lots = $this->activeLots;
        $lotIds = $lots->pluck('id');

        $last7Days = LivestockDailyEntry::whereIn('lot_id', $lotIds)
            // Ticket H6 — 🔴 `now()->subDays(6)` portait l'HEURE courante : la fiche de J-6 (minuit) sortait de la
            // fenêtre, et « Mortalité Cumulée (7j) » ne comptait que 6 jours. Bornes en DATES (Y-m-d) : J-6 à aujourd'hui, juste en MySQL comme en SQLite.
            ->whereBetween('entry_date', [now()->subDays(6)->toDateString(), now()->toDateString()])
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
                'ligne_poste' => $this->ligneDuPoste($species->code, $lots),
            ];
        });
    }

    /**
     * Ticket H11 — la 4ᵉ ligne propre à chaque filière (`_ligneDuPoste` du poste), formules reprises telles quelles.
     *
     * ⚠️ Mères / Géniteurs, Truies reproductrices et Taux d'éclosion valent « — » au poste (aucun décompte stocké, la
     * fiche Escargots n'a pas de colonne d'éclosion) : « — » ici aussi, jamais un chiffre que le poste n'affiche pas.
     * Taux de ponte : moyenne, sur les fiches DU MOIS des bandes au stade `ponte`, de (œufs ÷ effectif final × 100) —
     * œufs absents comptés 0, fiche à effectif nul écartée (`ProductionOeufsService.tauxDePonte`) ; écrit « 56.7% ».
     *
     * @return array{0: string, 1: string}|null
     */
    private function ligneDuPoste(string $code, Collection $lots): ?array
    {
        return match ($code) {
            'cuniculture' => ['Mères / Géniteurs', '—'],
            'porciculture' => ['Truies reproductrices', '—'],
            'helico' => ["Taux d'éclosion", '—'],
            'aviculture' => ['Taux de ponte', $this->tauxDePonteDuMois($lots)],
            default => null,
        };
    }

    private function tauxDePonteDuMois(Collection $lots): string
    {
        $enPonte = $lots->filter(fn ($lot) => ($lot->stage ?? '') === 'ponte')->pluck('id');

        $taux = LivestockDailyEntry::whereIn('lot_id', $enPonte)
            ->whereBetween('entry_date', [now()->startOfMonth()->toDateString(), now()->endOfMonth()->toDateString()])
            ->get()
            ->filter(fn ($e) => (int) $e->effectif_final > 0)
            ->map(fn ($e) => ((int) ($e->ponte_total ?? 0)) / (int) $e->effectif_final * 100);

        return $taux->isEmpty() ? '—' : number_format($taux->avg(), 1, '.', '').'%';
    }

    /**
     * Ticket H11 — série hebdomadaire du GMQ cumulé tel qu'il était connu à la fin de chaque semaine
     * (`_serieHebdomadaire` du poste) : moyenne NON arrondie des bandes qui avaient deux pesées, `null` sinon.
     *
     * @return array<int, ?float>
     */
    private function serieHebdomadaire(Collection $lots, int $semaines): array
    {
        $service = app(GrowthAnalysisService::class);
        $serie = [];

        for ($i = $semaines - 1; $i >= 0; $i--) {
            $borne = now()->startOfDay()->subDays(7 * $i)->toDateString();
            $valeurs = $lots->map(fn ($lot) => $service->gmqCumule($lot->id, $borne))->filter(fn ($v) => $v !== null);
            $serie[] = $valeurs->isEmpty() ? null : (float) $valeurs->avg();
        }

        return $serie;
    }

    private function lotsDeLEspece(string $code): Collection
    {
        return $this->activeLots->filter(fn ($lot) => $lot->species?->code === $code)->values();
    }

    /** Ticket H11 — courbe « Croissance (GMQ) par Espèce » de la Synthèse : 5 points (S1..S5) par espèce. */
    public function getGmqParEspeceParSemaineProperty(): array
    {
        $series = [];
        foreach (['cuniculture', 'aviculture', 'porciculture'] as $code) {
            $series[$code] = $this->serieHebdomadaire($this->lotsDeLEspece($code), 5);
        }

        return $series;
    }

    /**
     * Ticket H11 — rappels des 7 prochains jours (`_rappels` du poste) : traitements du barème DUS et NON ADMINISTRÉS,
     * bande par bande (le cycle vient du moteur UNIQUE `ProtocoleDuJourService` — une seconde copie de la règle
     * finirait par faire administrer un traitement au mauvais jour), puis les rémanences en cours ; tri par échéance.
     *
     * @return array<int, array{libelle: string, echeance: string, jours: int}>
     */
    public function getRappelsVmsProperty(): array
    {
        $moteur = app(ProtocoleDuJourService::class);
        $jour = now()->startOfDay();
        $rappels = [];

        foreach ($this->activeLots->sortBy('code')->values() as $bande) {
            if (! $bande->species) {
                continue;
            }

            for ($d = 0; $d <= self::HORIZON_RAPPELS; $d++) {
                foreach ($moteur->pourBande($bande, $jour->copy()->addDays($d))->traitements as $t) {
                    if ($t['deja_administre']) {
                        continue;   // un traitement déjà administré n'est plus un rappel : l'afficher ferait redoser
                    }
                    $rappels[] = [
                        'libelle' => $t['standard']->treatment.' — '.$bande->code,
                        'echeance' => $d === 0 ? "Aujourd'hui" : 'Dans '.$d.' jour'.($d > 1 ? 's' : ''),
                        'jours' => $d,
                    ];
                }
            }
        }

        // Rémanences en cours : des interdictions de vente en vigueur, que le poste mêle au bloc.
        foreach (VeterinaryWithdrawalPeriod::whereDate('end_date', '>=', $jour->toDateString())->get() as $r) {
            $restants = (int) round($jour->diffInDays($r->end_date->copy()->startOfDay()));
            $rappels[] = [
                'libelle' => 'Rémanence en cours — '.($r->product_used ?: 'traitement'),
                'echeance' => 'Fin dans '.$restants.' jour'.($restants > 1 ? 's' : ''),
                'jours' => $restants,
            ];
        }

        usort($rappels, fn ($a, $b) => $a['jours'] <=> $b['jours']);   // tri stable (PHP 8)

        return $rappels;
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
                    'derniere_date' => $weighIns->last()?->entry_date?->toDateString(),
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
                'derniere_date' => $last->entry_date->toDateString(),
            ];
        });
    }

    /** Ticket H11 — le tableau GMQ du Blade, filtré par espèce (seul le tableau suit le filtre, comme au poste). */
    public function getGmqTableFiltreeProperty()
    {
        return $this->espece === 'all'
            ? $this->gmqTable
            : $this->gmqTable->filter(fn ($row) => $row['lot']->species?->code === $this->espece)->values();
    }

    /**
     * Ticket H11 — cartes de l'onglet GMQ : moyenne NON arrondie des GMQ cumulés des bandes de l'espèce (affichée sans
     * décimale), `null` si aucune n'a deux pesées ; et « Lots Suivis (Pesées ≥ 2) ».
     *
     * Ticket U2 (D-U2) — `objectifs` : l'objectif de chaque carte, lu dans `growth_standards` pour les stades des
     * bandes MOYENNÉES par la carte (`GrowthAnalysisService::objectifPour` : barème du stade de chaque bande, comme
     * Analyse des Croissances, puis enveloppe min des minima / max des maxima) ; `null` sans barème (« — »).
     */
    public function getGmqCartesProperty(): array
    {
        $avecGmq = $this->gmqTable->filter(fn ($row) => $row['gmq'] !== null);
        $standards = GrowthStandard::all();
        $parEspece = [];
        $objectifs = [];

        foreach (self::ESPECES_CARTES_GMQ as $code) {
            $lignes = $avecGmq->filter(fn ($row) => $row['lot']->species?->code === $code);
            $valeurs = $lignes->pluck('gmq');
            $parEspece[$code] = $valeurs->isEmpty() ? null : (float) $valeurs->avg();
            $objectifs[$code] = GrowthAnalysisService::objectifPour($standards, $code, $lignes->map(fn ($row) => $row['lot']->stage));
        }

        return ['par_espece' => $parEspece, 'objectifs' => $objectifs, 'lots_suivis' => $avecGmq->count()];
    }

    /** Ticket H11 — bande de la courbe « Évolution du GMQ » : la dernière pesée la plus récente (à égalité, le code). */
    public function getBandeSuivieProperty(): ?LivestockLot
    {
        $suivie = $this->gmqTable->filter(fn ($row) => $row['gmq'] !== null)
            ->sort(fn ($a, $b) => [$b['derniere_date'], $a['lot']->code] <=> [$a['derniere_date'], $b['lot']->code])
            ->first();

        return $suivie['lot'] ?? null;
    }

    /** Ticket H11 — courbe 8 semaines de la bande suivie. */
    public function getEvolutionGmqProperty(): array
    {
        $suivie = $this->bandeSuivie;

        return $suivie === null ? [] : $this->serieHebdomadaire(collect([$suivie]), 8);
    }

    public function getSanitaireBySpeciesProperty()
    {
        return LivestockSpecies::enabled()->get()->map(function ($species) {
            // Bandes NON archivées (une bande clôturée ce mois-ci a bien reçu ses soins) ; soins archivés exclus.
            $lotIds = LivestockLot::where('species_id', $species->id)->where('is_active', true)->pluck('id');

            $records = VeterinaryRecord::whereIn('lot_id', $lotIds)->where('is_active', true)
                ->whereMonth('record_date', now()->month)->whereYear('record_date', now()->year);

            $effectifTotal = (int) LivestockLot::whereIn('id', $lotIds)->vivantes()->sum('current_quantity');
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
        $records = VeterinaryRecord::whereIn('lot_id', $lotIds)->where('is_active', true)   // soin archivé = supprimé
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
                // Ticket H11 — la droite elle-même, pour les ajouts du poste (sélecteur, horizons, cartes).
                'pente' => $slope,
                'ordonnee' => $intercept,
                'dernier_jour' => (int) $lastX,
                'nb_pesees' => $n,
                'poids_actuel_g' => (float) $weighIns->last()->weight_sample_avg_g,
            ];
        });
    }

    /** Ticket H11 — bandes projetables (3 pesées au moins), triées par code comme au poste. */
    public function getPrevisionsProjetablesProperty()
    {
        return $this->previsions->where('insufficient', false)->sortBy(fn ($row) => $row['lot']->code)->values();
    }

    /** Ticket H11 — bande retenue : celle du sélecteur, sinon la première (une sélection disparue retombe sur elle). */
    public function getPrevisionChoisieProperty(): ?array
    {
        $projetables = $this->previsionsProjetables;

        return $projetables->first(fn ($row) => $row['lot']->id === $this->bandePrevision) ?? $projetables->first();
    }

    /** Poids projeté `$jours` après la dernière pesée, arrondi à l'entier (`Prevision.projeter` du poste). */
    public static function projeter(array $prevision, int $jours): float
    {
        return round($prevision['ordonnee'] + $prevision['pente'] * ($prevision['dernier_jour'] + $jours));
    }

    public function render()
    {
        // Ticket H11 — le sélecteur du navigateur montre la bande réellement projetée (la première, faute de choix).
        if ($this->tab === 'prevision' && $this->bandePrevision === null) {
            $this->bandePrevision = $this->previsionChoisie['lot']->id ?? null;
        }

        return view('livewire.elevage.dashboard-elevage', ['title' => 'Élevage > Dashboard Élevage']);
    }
}
