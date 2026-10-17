<?php

namespace Tests\Feature;

use App\Livewire\Elevage\FicheLapins;
use App\Models\FeedRationStandard;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.11 (Sprint 14) — Rationnement Lapins relié aux Morts/Dons.
 *
 * Deux comportements sont verrouillés ici :
 *  1. les effectifs par catégorie sont réellement PERSISTÉS et CONTINUS d'un
 *     jour à l'autre — ils repartaient de zéro à chaque saisie ;
 *  2. « un Reproducteur MORT ne déduit que la ligne Reproducteur » — la
 *     règle exacte demandée par le client.
 *
 * 🔁 TICKET 15.41 — RÉÉCRIT : les effectifs Jeune / Lapin de Chair ne sont plus SAISIS à la main, ils sont
 * CALCULÉS par la chaîne (départ + mouvements par catégorie). La couverture est conservée, sur le nouveau
 * mécanisme : persistance et rechargement, continuité d'un jour à l'autre, « un Reproducteur mort ne déduit que
 * Reproducteur » (et désormais « chaque catégorie ne perd que ses propres morts »), ration appliquée à
 * l'effectif calculé, plancher à 0, valeur enregistrée = valeur calculée. Départ R20/J35/C45 = 100 (effectif
 * initial de la bande) ; les attendus sont des littéraux calculés à la main.
 */
class RationnementLapinsTest extends TestCase
{
    use RefreshDatabase;

    private LivestockLot $lot;

    protected function setUp(): void
    {
        parent::setUp();

        $species = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);

        $this->lot = LivestockLot::create([
            'code' => 'LOT-LAP-2026-06',
            'species_id' => $species->id,
            'stage' => 'engraissement',
            'initial_quantity' => 100,
            'current_quantity' => 100,
            'created_date' => '2026-06-01',
            'status' => 'actif',
            'is_active' => true,
        ]);

        // Barème réel (ticket 2.7).
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Reproducteur', 'ration_g_per_day' => 120]);
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Sevré', 'ration_g_per_day' => 30]);
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Jeune (engraissement)', 'ration_g_per_day' => 60]);
    }

    private function jour(string $date, array $attributs = []): LivestockDailyEntry
    {
        return LivestockDailyEntry::create(array_merge([
            'lot_id' => $this->lot->id,
            'entry_date' => $date,
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0,
            'effectif_final' => 100,
        ], $attributs));
    }

    /** Chaîne posée par l'écran lui-même : départ R20 / J35 / C45 (somme 100 = effectif initial) le 10/07/2026. */
    private function chaine(): void
    {
        Livewire::test(FicheLapins::class)
            ->set('selectedDate', '2026-07-10')
            ->set('departRepro', 20)
            ->set('departSevre', 35)
            ->set('departJeune', 45)
            ->call('saveDay');
    }

    /**
     * LE BUG CORRIGÉ : sans persistance, ces trois valeurs repartaient de zéro
     * à chaque changement de jour. Désormais elles sont DÉRIVÉES du départ, écrites en base
     * par la chaîne, et l'écran les relit.
     */
    public function test_category_headcounts_are_persisted_and_reloaded(): void
    {
        $this->chaine();

        $entry = LivestockDailyEntry::where('entry_date', '2026-07-10')->firstOrFail();

        $this->assertEquals(20, $entry->cat_eff_repro);
        $this->assertEquals(35, $entry->cat_eff_sevre);
        $this->assertEquals(45, $entry->cat_eff_jeune);

        // Rechargement du même jour : les valeurs reviennent, jamais zéro, jamais « — ».
        $cat = Livewire::test(FicheLapins::class)->call('loadDay', '2026-07-10')->instance()->categoriesJour;

        $this->assertSame([20, 35, 45], [$cat['repro'], $cat['sevre'], $cat['jeune']]);
    }

    /** Continuité : un jour non encore saisi reprend le dernier jour connu (calculé, pas ressaisi). */
    public function test_an_unsaved_day_carries_over_the_previous_values(): void
    {
        $this->chaine();

        $cat = Livewire::test(FicheLapins::class)->call('loadDay', '2026-07-11')->instance()->categoriesJour;

        $this->assertSame([20, 35, 45], [$cat['repro'], $cat['sevre'], $cat['jeune']]);
    }

    /**
     * LA RÈGLE DEMANDÉE PAR LE CLIENT : un Reproducteur mort ne déduit QUE la
     * ligne Reproducteur — jamais les Jeunes ni les Lapins de Chair.
     */
    public function test_a_dead_breeder_only_reduces_the_breeder_line(): void
    {
        $this->chaine();

        $component = Livewire::test(FicheLapins::class)
            ->call('loadDay', '2026-07-11')
            ->set('mortRepro', 2)
            ->set('donRepro', 1);

        // 20 − 2 morts − 1 don = 17
        $cat = $component->instance()->categoriesJour;
        $this->assertEquals(17, $cat['repro']);

        // Les deux autres catégories ne bougent pas d'un iota.
        $this->assertEquals(35, $cat['sevre']);
        $this->assertEquals(45, $cat['jeune']);
    }

    /** Réciproque (nouveau, 15.41) : chaque catégorie ne perd que SES morts — le Reproducteur n'est pas touché. */
    public function test_each_category_only_loses_its_own_dead(): void
    {
        $this->chaine();

        $cat = Livewire::test(FicheLapins::class)
            ->call('loadDay', '2026-07-11')
            ->set('mortChair', 5)        // Lapin de chair
            ->set('mortLapereau', 3)     // Lapereau = Jeune
            ->instance()->categoriesJour;

        $this->assertSame([20, 32, 40], [$cat['repro'], $cat['sevre'], $cat['jeune']]);
    }

    /** Sans historique (aucun départ), l'effectif n'est plus une saisie : « — », et le départ est proposé. */
    public function test_without_history_the_breeder_line_is_unknown_and_the_departure_is_offered(): void
    {
        $component = Livewire::test(FicheLapins::class)->set('selectedDate', '2026-07-10');

        $cat = $component->instance()->categoriesJour;
        $this->assertNull($cat['repro']);
        $this->assertNull($cat['sevre']);
        $this->assertNull($cat['jeune']);
        $this->assertTrue($cat['depart_requis']);
    }

    /** L'effectif calculé alimente réellement le rationnement. */
    public function test_the_ration_uses_the_computed_breeder_headcount(): void
    {
        $this->chaine();

        $component = Livewire::test(FicheLapins::class)
            ->call('loadDay', '2026-07-11')
            ->set('mortRepro', 5);

        // 20 − 5 = 15 reproducteurs × 120 g = 1 800 g
        $this->assertEquals(15, $component->instance()->categoriesJour['repro']);
        $this->assertEquals(1_800, $component->instance()->provendeCalculation['repro']['total_g']);
    }

    /** L'effectif Reproducteur ne peut jamais devenir négatif. */
    public function test_the_breeder_headcount_never_goes_negative(): void
    {
        Livewire::test(FicheLapins::class)
            ->set('selectedDate', '2026-07-10')
            ->set('departRepro', 3)->set('departSevre', 47)->set('departJeune', 50)
            ->call('saveDay');

        $component = Livewire::test(FicheLapins::class)
            ->call('loadDay', '2026-07-11')
            ->set('mortRepro', 10);      // plus de morts que d'effectif

        $this->assertEquals(0, $component->instance()->categoriesJour['repro']);
    }

    /** La valeur enregistrée est bien la valeur CALCULÉE. */
    public function test_saving_persists_the_computed_value(): void
    {
        $this->chaine();

        Livewire::test(FicheLapins::class)
            ->call('loadDay', '2026-07-11')
            ->set('mortRepro', 4)
            ->call('saveDay');

        $entry = LivestockDailyEntry::where('entry_date', '2026-07-11')->firstOrFail();

        $this->assertEquals(16, $entry->cat_eff_repro);
        $this->assertEquals(35, $entry->cat_eff_sevre);
        $this->assertEquals(45, $entry->cat_eff_jeune);
    }
}
