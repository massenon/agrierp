<?php

namespace Tests\Feature;

use App\Livewire\Rapports\ElevageSynth;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\StockMovement;
use App\Models\User;
use App\Services\EggStockLedgerService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.46 (Sprint 14) — GRAND LIVRE DE STOCK D'ŒUFS, point de vérité unique.
 *
 * Le Tableau 3 du rapport Synthèse Élevage affichait quatre colonnes vides au
 * motif qu'« un grand livre de stock d'œufs n'existe nulle part dans ce
 * projet ». Il existait depuis le ticket 14.13 — enfermé dans le composant
 * `FichePondeuses`. Extrait, il sert désormais les deux écrans.
 *
 * Les deux corrections durement acquises au ticket 14.13 sont reverrouillées
 * ici : le SRH se lit dans l'HISTORIQUE, pas dans le stock du jour présent ;
 * l'OS compte les VENTES seules, pas les casses.
 */
class GrandLivreOeufsTest extends TestCase
{
    use RefreshDatabase;

    private Product $oeufs;

    private LivestockLot $bande;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-rapports', 'view-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('admin', 'web');
        $role->givePermissionTo(['view-rapports', 'view-elevage']);

        $user = User::create([
            'name' => 'DG', 'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $user->assignRole($role);
        $this->actingAs($user);

        $espece = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'AVI', 'is_active' => true]);
        $categorie = ProductCategory::create(['label' => 'Œufs', 'is_active' => true]);

        $this->oeufs = Product::create([
            'sku' => 'AVI-002', 'name' => 'Œufs de table (plateau)', 'category_id' => $categorie->id,
            'species_id' => $espece->id, 'unit' => 'u', 'pricing_mode' => 'fourchette',
            'price_min' => 2_000, 'price_max' => 2_500, 'tva_rate' => 0,
            'stock_qty' => 999, 'is_active' => true,
        ]);

        $this->bande = LivestockLot::create([
            'code' => 'AVI-PONTE-01', 'species_id' => $espece->id, 'stage' => 'ponte',
            'initial_quantity' => 500, 'current_quantity' => 461,
            'created_date' => '2026-01-10', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    private function mouvement(float $qty, string $date, string $type, ?string $refType = null): void
    {
        StockMovement::create([
            'product_id' => $this->oeufs->id, 'type' => $type, 'quantity' => $qty,
            'movement_date' => $date, 'reference_type' => $refType ?? 'manual',
        ]);
    }

    private function ponte(int $recoltes, int $casses, string $date): void
    {
        LivestockDailyEntry::create([
            'lot_id' => $this->bande->id, 'entry_date' => $date,
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0,
            'effectif_final' => 461, 'ponte_total' => $recoltes, 'ponte_casses' => $casses,
        ]);
    }

    /** ⚠️ 30 œufs par plateau — valeur prouvée par les données du prototype. */
    public function test_thirty_eggs_make_one_tray(): void
    {
        $ledger = app(EggStockLedgerService::class);

        $this->assertEquals(['plateaux' => 7, 'vrac' => 8], $ledger->enPlateaux(218));
        $this->assertEquals(['plateaux' => 14, 'vrac' => 0], $ledger->enPlateaux(420));
    }

    /** Les formules du prototype, appliquées telles quelles. */
    public function test_the_prototype_formulas_hold(): void
    {
        $this->mouvement(210, '2026-07-01', 'entree');   // SRH = 210 plateaux

        // 428 commercialisables = 14 plateaux + 8 vrac.
        $ligne = app(EggStockLedgerService::class)->ligne('2026-07-13', 428);

        $this->assertEquals(210, $ligne['srh']);
        $this->assertEquals(224, $ligne['ts'], 'TS = (OR-OF) en plateaux + SRH.');
        $this->assertEquals(224, $ligne['final'], 'Aucune vente ce jour-la.');
    }

    /**
     * ⚠️ LE SRH SE LIT DANS L'HISTORIQUE, jamais dans le stock de MAINTENANT.
     * C'est le premier des deux défauts corrigés au ticket 14.13.
     */
    public function test_the_carry_over_reads_history_not_todays_stock(): void
    {
        $this->mouvement(100, '2026-07-01', 'entree');
        $this->mouvement(400, '2026-07-20', 'entree');   // postérieur : hors du SRH

        $this->assertEquals(100, app(EggStockLedgerService::class)->stockAvant('2026-07-13'));
        $this->assertNotEquals(
            (float) $this->oeufs->stock_qty,
            app(EggStockLedgerService::class)->stockAvant('2026-07-13'),
            'Le stock du jour present ne doit jamais tenir lieu de report.'
        );
    }

    /** ⚠️ L'OS compte les VENTES seules — une casse n'est pas une vente. */
    public function test_only_sales_count_as_outflow(): void
    {
        $this->mouvement(14, '2026-07-13', 'sortie', 'sale');
        $this->mouvement(3, '2026-07-13', 'sortie', 'stock_adjustment');

        $this->assertEquals(14, app(EggStockLedgerService::class)->ventesDu('2026-07-13'));
    }

    /** Le rapport expose réellement les quatre colonnes. */
    public function test_the_report_exposes_the_four_columns(): void
    {
        $this->mouvement(210, '2026-07-01', 'entree');
        $this->mouvement(14, '2026-07-13', 'sortie', 'sale');
        $this->ponte(432, 4, '2026-07-13');

        $ledger = Livewire::test(ElevageSynth::class, ['startDate' => '2026-07-01', 'endDate' => '2026-07-31'])
            ->set('activeTable', 't3')
            ->instance()->ledgerOeufs;

        $this->assertArrayHasKey('2026-07-13', $ledger);
        $this->assertEquals(210, $ledger['2026-07-13']['srh']);
        $this->assertEquals(224, $ledger['2026-07-13']['ts']);
        $this->assertEquals(14, $ledger['2026-07-13']['os']);
        $this->assertEquals(210, $ledger['2026-07-13']['final']);
    }

    /**
     * ⚠️ Deux bandes pondeuses le même jour : la production est agrégée UNE
     * seule fois, et le solde de ferme n'est pas compté deux fois.
     */
    public function test_two_laying_lots_on_one_day_share_a_single_farm_balance(): void
    {
        $seconde = LivestockLot::create([
            'code' => 'AVI-PONTE-02', 'species_id' => $this->bande->species_id, 'stage' => 'ponte',
            'initial_quantity' => 200, 'current_quantity' => 190,
            'created_date' => '2026-02-01', 'status' => 'actif', 'is_active' => true,
        ]);

        $this->mouvement(100, '2026-07-01', 'entree');
        $this->ponte(300, 0, '2026-07-13');                      // 10 plateaux
        LivestockDailyEntry::create([
            'lot_id' => $seconde->id, 'entry_date' => '2026-07-13',
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0,
            'effectif_final' => 190, 'ponte_total' => 180, 'ponte_casses' => 0,   // 6 plateaux
        ]);

        $ledger = Livewire::test(ElevageSynth::class, ['startDate' => '2026-07-01', 'endDate' => '2026-07-31'])
            ->set('activeTable', 't3')
            ->instance()->ledgerOeufs;

        $this->assertCount(1, $ledger, 'Une seule ligne de grand livre pour la journee.');
        $this->assertEquals(116, $ledger['2026-07-13']['ts'], '100 reportes + 16 plateaux produits.');
    }
}
