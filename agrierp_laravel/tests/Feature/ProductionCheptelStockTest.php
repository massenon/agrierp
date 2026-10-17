<?php

namespace Tests\Feature;

use App\Actions\SyncLotProductionStockAction;
use App\Livewire\Elevage\GestionBandes;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\StockMovement;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.37 (Sprint 14) — LA PRODUCTION DU CHEPTEL ENTRE EN STOCK.
 *
 * Le défaut : une naissance augmentait l'effectif d'une bande sans jamais créer
 * de marchandise vendable. Une exploitation qui élève ses propres animaux ne
 * pouvait donc les vendre qu'à hauteur de son inventaire d'ouverture.
 *
 * Les deux points qui comptent : le calcul est DIFFÉRENTIEL (corriger une fiche
 * ne recompte pas la production), et achats comme ventes sont EXCLUS parce
 * qu'ils sont déjà comptés par leurs propres flux.
 */
class ProductionCheptelStockTest extends TestCase
{
    use RefreshDatabase;

    private LivestockLot $lot;

    private Product $lapereau;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('animalier', 'web');
        $role->givePermissionTo(['view-elevage', 'manage-elevage']);

        $user = User::create([
            'name' => 'Animalier', 'email' => 'production@olouwachegoun.bj', 'password' => bcrypt('AgriERP@2026'),
        ]);
        $user->assignRole($role);
        $this->actingAs($user);

        $espece = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Cuniculture', 'is_enabled' => true]);
        $categorie = ProductCategory::create(['label' => 'Cuniculture', 'is_active' => true]);

        $this->lapereau = Product::create([
            'sku' => 'CUN-002', 'name' => 'Lapereau sevré', 'category_id' => $categorie->id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 1_200, 'price_max' => 1_800,
            'tva_rate' => 0, 'stock_qty' => 10, 'species_id' => $espece->id, 'is_active' => true,
        ]);

        $this->lot = LivestockLot::create([
            'code' => 'CUN-2026-01', 'species_id' => $espece->id, 'product_id' => $this->lapereau->id,
            'stage' => 'reproduction', 'initial_quantity' => 60, 'current_quantity' => 60,
            'created_date' => now()->subMonths(2)->format('Y-m-d'), 'status' => 'actif', 'is_active' => true,
        ]);
    }

    private function fiche(array $valeurs): LivestockDailyEntry
    {
        return LivestockDailyEntry::create(array_merge([
            'lot_id' => $this->lot->id,
            'entry_date' => now()->format('Y-m-d'),
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0,
            'effectif_final' => 60,
        ], $valeurs));
    }

    /** LE DÉFAUT CORRIGÉ : une naissance crée de la marchandise. */
    public function test_a_birth_enters_the_sellable_stock(): void
    {
        app(SyncLotProductionStockAction::class)->execute($this->fiche(['ne' => 6]));

        $this->assertEquals(16, (float) $this->lapereau->fresh()->stock_qty);
        $this->assertEquals(1, StockMovement::where('reference_type', 'elevage')->count());
    }

    /** La mortalité retire la marchandise, sinon le stock dériverait au-dessus du cheptel. */
    public function test_a_death_removes_it_again(): void
    {
        app(SyncLotProductionStockAction::class)->execute($this->fiche(['ne' => 6, 'mort' => 2]));

        $this->assertEquals(14, (float) $this->lapereau->fresh()->stock_qty, '10 + 6 - 2.');
    }

    /** Un don sort aussi du stock : le sujet quitte l'exploitation. */
    public function test_a_gift_removes_it_too(): void
    {
        app(SyncLotProductionStockAction::class)->execute($this->fiche(['ne' => 4, 'don' => 1]));

        $this->assertEquals(13, (float) $this->lapereau->fresh()->stock_qty);
    }

    /**
     * ⚠️ ACHATS ET VENTES EXCLUS — ils sont déjà comptés par leurs propres
     * flux (`EnregistrerAchat` et le POS). Les recompter ici doublerait chaque
     * mouvement.
     */
    public function test_purchases_and_sales_are_not_counted_twice(): void
    {
        app(SyncLotProductionStockAction::class)->execute($this->fiche(['achat' => 20, 'vente' => 5]));

        $this->assertEquals(10, (float) $this->lapereau->fresh()->stock_qty, 'Le stock ne bouge pas.');
        $this->assertEquals(0, StockMovement::count(), 'Aucun mouvement fantome.');
    }

    /**
     * LE POINT CENTRAL : calcul DIFFÉRENTIEL. Corriger une fiche ne recompte
     * pas la production — c'est la limitation documentée dans `FichePondeuses`
     * qui tombe ici.
     */
    public function test_correcting_a_sheet_applies_only_the_difference(): void
    {
        $action = app(SyncLotProductionStockAction::class);

        $entree = $this->fiche(['ne' => 6]);
        $action->execute($entree);
        $this->assertEquals(16, (float) $this->lapereau->fresh()->stock_qty);

        // L'éleveur revient sur sa journée : 8 naissances, pas 6.
        $avant = ['ne' => 6, 'mort' => 0, 'don' => 0];
        $entree->update(['ne' => 8]);
        $action->execute($entree->fresh(), $avant);

        $this->assertEquals(18, (float) $this->lapereau->fresh()->stock_qty,
            'Seules les 2 naissances supplementaires sont ajoutees.');
    }

    /** Réenregistrer une fiche inchangée ne produit aucun mouvement. */
    public function test_saving_an_unchanged_sheet_moves_nothing(): void
    {
        $action = app(SyncLotProductionStockAction::class);

        $entree = $this->fiche(['ne' => 5, 'mort' => 1]);
        $action->execute($entree);

        $stock = (float) $this->lapereau->fresh()->stock_qty;
        $mouvements = StockMovement::count();

        $action->execute($entree->fresh(), ['ne' => 5, 'mort' => 1, 'don' => 0]);

        $this->assertEquals($stock, (float) $this->lapereau->fresh()->stock_qty);
        $this->assertEquals($mouvements, StockMovement::count(), 'Aucun mouvement a zero au journal.');
    }

    /** Une correction à la baisse retire bien du stock. */
    public function test_a_downward_correction_removes_stock(): void
    {
        $action = app(SyncLotProductionStockAction::class);

        $entree = $this->fiche(['ne' => 9]);
        $action->execute($entree);

        $entree->update(['ne' => 3]);
        $action->execute($entree->fresh(), ['ne' => 9, 'mort' => 0, 'don' => 0]);

        $this->assertEquals(13, (float) $this->lapereau->fresh()->stock_qty, '10 + 9 puis -6.');
    }

    /**
     * ⚠️ SANS PRODUIT RATTACHÉ, RIEN NE SE PRODUIT. Le rattachement est une
     * décision de l'exploitant : une bande peut légitimement n'en avoir aucun.
     */
    public function test_a_lot_without_a_product_generates_no_movement(): void
    {
        $this->lot->update(['product_id' => null]);

        app(SyncLotProductionStockAction::class)->execute($this->fiche(['ne' => 6]));

        $this->assertEquals(10, (float) $this->lapereau->fresh()->stock_qty);
        $this->assertEquals(0, StockMovement::count());
    }

    /** Le rattachement se saisit à la création de la bande. */
    public function test_the_product_link_is_set_when_creating_a_band(): void
    {
        Livewire::test(GestionBandes::class)
            ->call('newLot')
            // ⚠️ Espèce D'ABORD : `updatedSpeciesId()` régénère le code suggéré
            // et écraserait une saisie antérieure.
            ->set('species_id', $this->lot->species_id)
            ->set('code', 'CUN-2026-99')
            ->set('stage', 'engraissement')
            ->set('created_date', now()->format('Y-m-d'))
            ->set('quantity', 40)
            ->set('product_id', $this->lapereau->id)
            ->call('saveLot')
            ->assertHasNoErrors();

        $this->assertEquals($this->lapereau->id, LivestockLot::where('code', 'CUN-2026-99')->value('product_id'));
    }

    /** Les produits proposés se limitent à la filière choisie, intrants exclus. */
    public function test_only_products_of_the_chosen_species_are_offered(): void
    {
        $autreCategorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);

        Product::create([
            'sku' => 'ALI-004', 'name' => 'Aliment lapins 25kg', 'category_id' => $autreCategorie->id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'price_min' => 7_250, 'price_max' => 8_250,
            'tva_rate' => 0, 'stock_qty' => 20, 'species_id' => $this->lot->species_id, 'is_active' => true,
        ]);

        $candidats = Livewire::test(GestionBandes::class)
            ->set('species_id', $this->lot->species_id)
            ->instance()
            ->produitsCandidats
            ->pluck('sku')
            ->all();

        $this->assertContains('CUN-002', $candidats);
        $this->assertNotContains('ALI-004', $candidats, "On ne produit pas de la provende avec un elevage.");
    }
}
