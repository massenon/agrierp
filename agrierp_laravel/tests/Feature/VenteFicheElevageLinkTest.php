<?php

namespace Tests\Feature;

use App\Livewire\Elevage\FicheLapins;
use App\Livewire\Ventes\PosInterface;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.4 — Lien Vente → Fiche Élevage.
 *
 * Spécification d'origine : `assets/js/agrisync-store.js` du prototype
 * (`addVente()` → `recordFicheVente()`), jamais transposée côté Laravel
 * jusqu'ici malgré une mention « livré » au log du Sprint 12.
 *
 * Le second test est le plus important : il couvre le bug réel qui rendait
 * la fonctionnalité inutilisable même une fois construite — `saveDay()`
 * réécrivait `vente` à zéro à chaque enregistrement de la journée.
 */
class VenteFicheElevageLinkTest extends TestCase
{
    use RefreshDatabase;

    private array $ctx = [];

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-ventes', 'manage-ventes', 'view-elevage', 'manage-elevage'] as $name) {
            Permission::findOrCreate($name, 'web');
        }
        $role = Role::findOrCreate('admin', 'web');
        $role->givePermissionTo(['view-ventes', 'manage-ventes', 'view-elevage', 'manage-elevage']);

        $user = User::create([
            'name' => 'Admin Test',
            'email' => 'dg.test@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'),
        ]);
        $user->assignRole($role);
        $this->actingAs($user);

        FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);

        $species = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);

        $lot = LivestockLot::create([
            'code' => 'LOT-LAP-2026-06',   // numérotation de référence du projet
            'species_id' => $species->id,
            'stage' => 'engraissement',
            'initial_quantity' => 40,
            'current_quantity' => 40,
            'created_date' => now()->subMonth()->format('Y-m-d'),
            'status' => 'actif',
            'is_active' => true,
        ]);

        $category = ProductCategory::create(['label' => 'Sujets vivants', 'is_active' => true]);

        $product = Product::create([
            'sku' => 'LAP-001',
            'name' => 'Lapin vif',
            'category_id' => $category->id,
            'unit' => 'pièce',
            'pricing_mode' => 'fourchette',
            'price_min' => 3000,
            'price_max' => 5000,
            'stock_qty' => 40,
            'species_id' => $species->id,   // c'est ce lien qui déclenche la répercussion
            'is_active' => true,
        ]);

        $this->ctx = compact('species', 'lot', 'product');
    }

    private function sell(int $qty, float $montant): void
    {
        Livewire::test(PosInterface::class)
            ->set('cart', [[
                'product_id' => $this->ctx['product']->id,
                'name' => $this->ctx['product']->name,
                'unit' => $this->ctx['product']->unit,
                'lot_id' => $this->ctx['lot']->id,
                'lot_code' => $this->ctx['lot']->code,
                'qty' => $qty,
                'montant' => $montant,
            ]])
            ->set('paymentMode', 'especes')
            ->set('cashReceived', $montant)
            ->call('validateSale');
    }

    public function test_a_pos_sale_of_live_animals_feeds_the_daily_fiche_and_the_lot(): void
    {
        $this->sell(3, 12_000);

        $entry = LivestockDailyEntry::where('lot_id', $this->ctx['lot']->id)
            ->where('entry_date', now()->format('Y-m-d'))
            ->first();

        $this->assertNotNull($entry, 'La vente doit créer la fiche journalière de la bande vendue.');
        $this->assertEquals(3, $entry->vente);

        // Effectif Final = Effectif(J-1) + Achats + Nés − (Morts + Ventes + Dons)
        $this->assertEquals(37, $entry->effectif_final);

        // La bande suit réellement — jamais seulement le stock produit.
        $this->assertEquals(37, $this->ctx['lot']->fresh()->current_quantity);
    }

    public function test_two_sales_the_same_day_accumulate_instead_of_overwriting(): void
    {
        $this->sell(3, 12_000);
        $this->sell(2, 8_000);

        $entry = LivestockDailyEntry::where('lot_id', $this->ctx['lot']->id)->first();

        $this->assertEquals(5, $entry->vente, 'Le compteur du jour doit cumuler, comme `recordFicheVente()` du prototype.');
        $this->assertEquals(35, $entry->effectif_final);
    }

    /**
     * LE CAS QUI RENDAIT LA FONCTIONNALITÉ INUTILISABLE : l'animalier
     * enregistre sa journée après une vente. Avant ce ticket, `saveDay()`
     * réécrivait `vente` à `0` en dur — la vente disparaissait de la fiche
     * et l'effectif remontait silencieusement.
     */
    public function test_saving_the_day_after_a_sale_does_not_wipe_it(): void
    {
        $this->sell(3, 12_000);

        Livewire::test(FicheLapins::class)
            ->set('selectedDate', now()->format('Y-m-d'))
            ->set('mortRepro', 1)          // l'animalier saisit 1 mort
            ->call('saveDay');

        $entry = LivestockDailyEntry::where('lot_id', $this->ctx['lot']->id)
            ->where('entry_date', now()->format('Y-m-d'))
            ->first();

        $this->assertEquals(3, $entry->vente, 'La vente du POS ne doit jamais être écrasée par la saisie journalière.');
        $this->assertEquals(1, $entry->mort);

        // 40 − (1 mort + 3 ventes) = 36
        $this->assertEquals(36, $entry->effectif_final);
    }

    public function test_a_product_not_linked_to_a_lot_leaves_the_fiches_untouched(): void
    {
        $category = ProductCategory::create(['label' => 'Provende', 'is_active' => true]);
        $feed = Product::create([
            'sku' => 'ALI-001',
            'name' => 'Aliment ponte',
            'category_id' => $category->id,
            'unit' => 'kg',
            'pricing_mode' => 'fourchette',
            'price_min' => 500,
            'price_max' => 700,
            'stock_qty' => 200,
            'is_active' => true,
        ]);

        Livewire::test(PosInterface::class)
            ->set('cart', [[
                'product_id' => $feed->id,
                'name' => $feed->name,
                'unit' => $feed->unit,
                'lot_id' => null,
                'lot_code' => null,
                'qty' => 10,
                'montant' => 6_000,
            ]])
            ->set('paymentMode', 'especes')
            ->set('cashReceived', 6_000)
            ->call('validateSale');

        $this->assertEquals(0, LivestockDailyEntry::count());
        $this->assertEquals(40, $this->ctx['lot']->fresh()->current_quantity);
    }
}
