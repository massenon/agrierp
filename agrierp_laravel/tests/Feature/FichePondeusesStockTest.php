<?php

namespace Tests\Feature;

use App\Actions\AdjustStockAction;
use App\Livewire\Elevage\FichePondeuses;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.13 (Sprint 14) — SRH / TS / OS de la Fiche Pondeuses.
 *
 * Les deux défauts corrigés se manifestaient en silence : un « Stock Reporté
 * Hier » qui affichait en réalité le stock du jour présent, et des ventes du
 * jour figées à zéro. Aucune erreur n'était levée — seuls les chiffres
 * étaient faux.
 */
class FichePondeusesStockTest extends TestCase
{
    use RefreshDatabase;

    private Product $oeufs;

    protected function setUp(): void
    {
        parent::setUp();

        $species = LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Volailles', 'is_enabled' => true]);

        LivestockLot::create([
            'code' => 'LOT-PON-2026-01',
            'species_id' => $species->id,
            'stage' => 'ponte',
            'initial_quantity' => 200,
            'current_quantity' => 200,
            'created_date' => '2026-06-01',
            'status' => 'actif',
            'is_active' => true,
        ]);

        $category = ProductCategory::create(['label' => 'Œufs', 'is_active' => true]);

        $this->oeufs = Product::create([
            'sku' => 'OEUF-PLATEAU',
            'name' => 'Plateau d’œufs',
            'category_id' => $category->id,
            'unit' => 'plateau',
            'pricing_mode' => 'fourchette',
            'price_min' => 2000,
            'price_max' => 2500,
            'stock_qty' => 0,
            'species_id' => $species->id,
            'is_active' => true,
        ]);
    }

    private function mouvement(float $delta, string $date, string $referenceType): void
    {
        app(AdjustStockAction::class)->execute(
            $this->oeufs->fresh(),
            $delta,
            $referenceType,
            null,
            \Carbon\Carbon::parse($date)
        );
    }

    /**
     * LE DÉFAUT PRINCIPAL : consulter un jour passé doit montrer le stock de
     * CE jour-là, pas celui d'aujourd'hui.
     */
    public function test_srh_is_the_balance_of_the_day_before_the_consulted_date(): void
    {
        $this->mouvement(10, '2026-07-01', 'daily_entry');   // +10
        $this->mouvement(6, '2026-07-05', 'daily_entry');    // +6  -> 16
        $this->mouvement(-4, '2026-07-08', 'sale');          // -4  -> 12

        $component = Livewire::test(FichePondeuses::class);

        // Au 05/07, le report de la veille ne connaît que le mouvement du 01/07.
        $component->set('selectedDate', '2026-07-05');
        $this->assertEquals(10.0, $component->instance()->stockToday['srh']);

        // Au 08/07, il connaît les deux entrées mais pas la vente du jour même.
        $component->set('selectedDate', '2026-07-08');
        $this->assertEquals(16.0, $component->instance()->stockToday['srh']);

        // Le stock actuel du produit (12) ne doit JAMAIS être servi comme SRH
        // d'une date antérieure — c'était précisément le bug.
        $this->assertEquals(12.0, (float) $this->oeufs->fresh()->stock_qty);
    }

    /** OS reflète les ventes réelles du jour, plus jamais un zéro figé. */
    public function test_os_reflects_the_real_sales_of_the_day(): void
    {
        $this->mouvement(20, '2026-07-01', 'daily_entry');
        $this->mouvement(-3, '2026-07-08', 'sale');
        $this->mouvement(-2, '2026-07-08', 'sale');
        $this->mouvement(-7, '2026-07-09', 'sale');   // autre jour, ne doit pas compter

        $component = Livewire::test(FichePondeuses::class)->set('selectedDate', '2026-07-08');

        $this->assertEquals(5.0, $component->instance()->stockToday['os']);
    }

    /** Une casse ou un ajustement n'est pas une vente. */
    public function test_only_sales_count_as_os(): void
    {
        $this->mouvement(20, '2026-07-01', 'daily_entry');
        $this->mouvement(-3, '2026-07-08', 'sale');
        $this->mouvement(-6, '2026-07-08', 'adjustment');   // casse d'inventaire

        $component = Livewire::test(FichePondeuses::class)->set('selectedDate', '2026-07-08');

        $this->assertEquals(3.0, $component->instance()->stockToday['os'], "Un ajustement n'est pas une vente.");
    }

    /**
     * La production du jour est comptée UNE SEULE FOIS : elle arrive par le
     * formulaire (plateaux), et son mouvement — daté du jour — est exclu du
     * SRH. Le total ne doit pas doubler une fois la journée enregistrée.
     */
    public function test_the_day_production_is_never_counted_twice(): void
    {
        $this->mouvement(10, '2026-07-01', 'daily_entry');       // report = 10
        $this->mouvement(4, '2026-07-08', 'daily_entry');        // production du jour, déjà enregistrée

        $component = Livewire::test(FichePondeuses::class)
            ->set('selectedDate', '2026-07-08')
            ->set('oeufsRecoltes', 120)     // 120 œufs
            ->set('oeufsCasses', 0);

        $stock = $component->instance()->stockToday;

        $this->assertEquals(10.0, $stock['srh'], 'Le SRH exclut la production du jour même.');
        $this->assertEquals(4, $component->instance()->plateaux['plateaux']);   // 120 / 30
        $this->assertEquals(14.0, $stock['ts'], 'Total = report + production du jour, comptée une fois.');
    }

    public function test_final_stock_deducts_the_days_sales(): void
    {
        $this->mouvement(10, '2026-07-01', 'daily_entry');
        $this->mouvement(-2, '2026-07-08', 'sale');

        $component = Livewire::test(FichePondeuses::class)
            ->set('selectedDate', '2026-07-08')
            ->set('oeufsRecoltes', 60)      // 2 plateaux
            ->set('oeufsCasses', 0);

        $stock = $component->instance()->stockToday;

        $this->assertEquals(10.0, $stock['srh']);
        $this->assertEquals(12.0, $stock['ts']);     // 10 + 2
        $this->assertEquals(2.0, $stock['os']);
        $this->assertEquals(10.0, $stock['final']);  // 12 − 2
    }

    public function test_no_egg_product_yields_zeroes_not_errors(): void
    {
        $this->oeufs->update(['is_active' => false, 'species_id' => null]);

        $component = Livewire::test(FichePondeuses::class)->set('selectedDate', '2026-07-08');

        $stock = $component->instance()->stockToday;

        $this->assertEquals(0.0, $stock['srh']);
        $this->assertEquals(0.0, $stock['os']);
    }
}
