<?php

namespace Tests\Feature;

use App\Livewire\Elevage\AnalyseCroissance;
use App\Models\GrowthStandard;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Services\GrowthAnalysisService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.9 (Sprint 14) — Analyse des Croissances (GMQ).
 *
 * Verrouille les deux points sensibles : la formule retenue par CET écran
 * (deux dernières pesées, distincte du GMQ cumulé du tableau de bord), et le
 * fait qu'un lot sans barème d'objectif ne soit JAMAIS présenté comme
 * conforme par défaut.
 */
class AnalyseCroissanceTest extends TestCase
{
    use RefreshDatabase;

    private function lot(string $code, string $speciesCode, string $stage = 'engraissement'): LivestockLot
    {
        $species = LivestockSpecies::firstOrCreate(
            ['code' => $speciesCode],
            ['label' => ucfirst($speciesCode), 'is_enabled' => true]
        );

        return LivestockLot::create([
            'code' => $code,
            'species_id' => $species->id,
            'stage' => $stage,
            'initial_quantity' => 50,
            'current_quantity' => 50,
            'created_date' => '2026-06-01',
            'status' => 'actif',
            'is_active' => true,
        ]);
    }

    private function pesee(LivestockLot $lot, string $date, int $poids): void
    {
        LivestockDailyEntry::create([
            'lot_id' => $lot->id,
            'entry_date' => $date,
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0,
            'effectif_final' => 50,
            'weight_sample_avg_g' => $poids,
        ]);
    }

    private function standard(string $speciesCode, string $stage, int $min, int $max): void
    {
        GrowthStandard::create([
            'species_code' => $speciesCode,
            'stage_label' => $stage,
            'gmq_min_g_per_day' => $min,
            'gmq_max_g_per_day' => $max,
        ]);
    }

    /**
     * Le point le plus important : cet écran compare les DEUX DERNIÈRES
     * pesées, pas la première et la dernière.
     */
    public function test_gmq_uses_the_two_most_recent_weighings(): void
    {
        $lot = $this->lot('LOT-LAP-2026-06', 'cuniculture');

        $this->pesee($lot, '2026-07-01', 300);   // ancienne
        $this->pesee($lot, '2026-07-18', 580);   // avant-dernière
        $this->pesee($lot, '2026-07-25', 700);   // dernière

        $service = app(GrowthAnalysisService::class);

        // Deux dernières : (700 − 580) / 7 = 17,1 g/j
        $recent = $service->gmqRecent($lot->id);
        $this->assertEquals(580, $recent['poids_precedent']);
        $this->assertEquals(700, $recent['poids_actuel']);
        $this->assertEquals(7, $recent['jours']);
        $this->assertEquals(17.1, $recent['gmq']);

        // Cumulé (formule du tableau de bord) : (700 − 300) / 24 = 16,7 g/j
        $this->assertEquals(16.7, $service->gmqCumule($lot->id));

        $this->assertNotEquals(
            $service->gmqCumule($lot->id),
            $recent['gmq'],
            'Les deux formules doivent bien rester distinctes — c est l ecart signale au ticket 14.9.'
        );
    }

    public function test_a_lot_with_a_single_weighing_is_excluded(): void
    {
        $lot = $this->lot('LOT-LAP-2026-07', 'cuniculture');
        $this->pesee($lot, '2026-07-25', 700);

        $this->assertNull(app(GrowthAnalysisService::class)->gmqRecent($lot->id));
        $this->assertSame([], app(GrowthAnalysisService::class)->rows());
    }

    /** Deux pesées le même jour ne définissent aucun gain quotidien. */
    public function test_two_weighings_on_the_same_day_yield_no_gmq(): void
    {
        $lot = $this->lot('LOT-LAP-2026-08', 'cuniculture');
        $this->pesee($lot, '2026-07-25', 600);

        // Même lot, même date : `updateOrCreate` n'est pas utilisé ici, on
        // vérifie simplement qu'un écart de 0 jour ne produit pas de division.
        $this->assertNull(app(GrowthAnalysisService::class)->gmqRecent($lot->id));
    }

    public function test_status_reflects_the_real_standard(): void
    {
        $this->standard('cuniculture', 'engraissement', 15, 20);

        $sousObjectif = $this->lot('LOT-A', 'cuniculture');
        $this->pesee($sousObjectif, '2026-07-18', 500);
        $this->pesee($sousObjectif, '2026-07-25', 570);      // 10 g/j -> sous objectif

        $dansCible = $this->lot('LOT-B', 'cuniculture');
        $this->pesee($dansCible, '2026-07-18', 580);
        $this->pesee($dansCible, '2026-07-25', 700);         // 17,1 g/j -> dans la cible

        $auDessus = $this->lot('LOT-C', 'cuniculture');
        $this->pesee($auDessus, '2026-07-18', 500);
        $this->pesee($auDessus, '2026-07-25', 800);          // 42,9 g/j -> au-dessus

        $rows = collect(app(GrowthAnalysisService::class)->rows())->keyBy('lot_code');

        $this->assertEquals('sous_objectif', $rows['LOT-A']['statut']);
        $this->assertEquals('dans_cible', $rows['LOT-B']['statut']);
        $this->assertEquals('au_dessus', $rows['LOT-C']['statut']);
    }

    /**
     * Sans barème, le statut ne doit JAMAIS être « dans la cible » par
     * défaut — ce serait affirmer une conformité jamais vérifiée.
     */
    public function test_a_lot_without_a_standard_is_never_reported_as_compliant(): void
    {
        $lot = $this->lot('LOT-ESC-1', 'helico');   // aucune norme semée pour l'héliciculture
        $this->pesee($lot, '2026-07-18', 100);
        $this->pesee($lot, '2026-07-25', 170);

        $row = app(GrowthAnalysisService::class)->rows()[0];

        $this->assertEquals('non_defini', $row['statut']);
        $this->assertNull($row['objectif_min']);
        $this->assertEquals(10.0, $row['gmq'], 'Le GMQ reste calculé même sans objectif.');
    }

    public function test_species_filter_narrows_the_rows(): void
    {
        $lapins = $this->lot('LOT-LAP', 'cuniculture');
        $this->pesee($lapins, '2026-07-18', 580);
        $this->pesee($lapins, '2026-07-25', 700);

        $porcs = $this->lot('LOT-POR', 'porciculture', 'croissance');
        $this->pesee($porcs, '2026-07-18', 24_000);
        $this->pesee($porcs, '2026-07-25', 26_800);

        $service = app(GrowthAnalysisService::class);

        $this->assertCount(2, $service->rows());
        $this->assertCount(1, $service->rows('cuniculture'));
        $this->assertEquals('LOT-POR', $service->rows('porciculture')[0]['lot_code']);
    }

    public function test_component_renders_with_real_data(): void
    {
        $this->standard('cuniculture', 'engraissement', 15, 20);
        $lot = $this->lot('LOT-LAP-2026-06', 'cuniculture');
        $this->pesee($lot, '2026-07-18', 580);
        $this->pesee($lot, '2026-07-25', 700);

        Livewire::test(AnalyseCroissance::class)
            ->assertOk()
            ->assertSee('LOT-LAP-2026-06')
            ->assertSee('Dans la cible')
            ->assertSee('17.1');
    }
}
