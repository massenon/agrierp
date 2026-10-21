<?php

namespace Tests\Feature;

use App\Actions\RecordEggProductionStockAction;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\StockMovement;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.59 (Sprint 14) — LA PONTE DU JOUR ENTRE AU STOCK.
 *
 * ⚠️⚠️ CE QUE CES TESTS PROTÈGENT. La maquette annonce « Incrémentation
 * Automatique du Stock : +N Plateaux au Stock Produits ». La règle vivait à
 * l'intérieur de l'écran Livewire : une ponte saisie hors ligne sur un poste
 * arrivait donc au serveur comme une **ligne morte**, `ponte_total` renseigné
 * et pas un œuf au stock.
 *
 * Les deux tests de garde sont les plus importants : les œufs des
 * reproducteurs et des escargots ne sont **pas** des œufs de table.
 */
class EggProductionStockTest extends TestCase
{
    use RefreshDatabase;

    private Product $oeufs;

    protected function setUp(): void
    {
        parent::setUp();

        $categorie = new ProductCategory();
        $categorie->id = '11111111-1111-4111-8111-111111111111';
        $categorie->label = 'Produits animaux';
        $categorie->is_active = true;
        $categorie->save();

        // ⚠️ LIGATURE EN MAJUSCULE, comme au catalogue réel : la résolution du
        // produit se fait sur un libellé normalisé, et un « Œ » qui ne serait
        // pas rapproché de « œ » ferait retomber tout le grand livre à zéro
        // sans la moindre erreur.
        $this->oeufs = Product::create([
            'sku' => 'OEUF-PLT', 'name' => 'Œufs de table (plateau)',
            'category_id' => $categorie->id, 'unit' => 'plateau',
            'pricing_mode' => 'fourchette', 'tva_rate' => 0,
            'stock_qty' => 0, 'is_active' => true,
        ]);
    }

    private function bande(string $codeEspece, string $stade): LivestockLot
    {
        $espece = LivestockSpecies::firstOrCreate(
            ['code' => $codeEspece],
            ['label' => ucfirst($codeEspece), 'is_active' => true],
        );

        return LivestockLot::create([
            'code' => 'LOT-'.strtoupper($stade),
            'species_id' => $espece->id,
            'stage' => $stade,
            'initial_quantity' => 200,
            'current_quantity' => 200,
            'created_date' => now()->toDateString(),
            'status' => 'actif',
            'is_active' => true,
        ]);
    }

    private function fiche(LivestockLot $lot, int $recoltes, int $casses): LivestockDailyEntry
    {
        return LivestockDailyEntry::create([
            'lot_id' => $lot->id,
            'entry_date' => now()->toDateString(),
            'ponte_total' => $recoltes,
            'ponte_casses' => $casses,
            'effectif_final' => 200,
        ]);
    }

    /** 435 œufs récoltés − 15 cassés = 420 commercialisables = 14 plateaux. */
    public function test_the_days_laying_increments_the_egg_stock(): void
    {
        $fiche = $this->fiche($this->bande('aviculture', 'ponte'), 435, 15);

        $plateaux = app(RecordEggProductionStockAction::class)->execute($fiche);

        $this->assertEquals(14, $plateaux);
        $this->assertEquals(14.0, (float) $this->oeufs->fresh()->stock_qty);
    }

    /** Le reliquat inférieur à 30 reste en vrac : il n'entre pas au stock. */
    public function test_the_remainder_below_a_full_tray_does_not_enter_stock(): void
    {
        $fiche = $this->fiche($this->bande('aviculture', 'ponte'), 29, 0);

        $this->assertEquals(0, app(RecordEggProductionStockAction::class)->execute($fiche));
        $this->assertEquals(0.0, (float) $this->oeufs->fresh()->stock_qty);
    }

    /**
     * ⚠️⚠️ GARDE 1 — LES ŒUFS À COUVER NE SONT PAS DES ŒUFS DE TABLE. La fiche
     * Reproducteurs renseigne aussi `ponte_total` ; déclencher sur la seule
     * présence du champ ferait entrer des œufs à couver au stock commercial.
     */
    public function test_a_breeding_lot_never_feeds_the_table_egg_stock(): void
    {
        $fiche = $this->fiche($this->bande('aviculture', 'reproduction'), 600, 0);

        $this->assertEquals(0, app(RecordEggProductionStockAction::class)->execute($fiche));
        $this->assertEquals(0.0, (float) $this->oeufs->fresh()->stock_qty);
    }

    /** ⚠️⚠️ GARDE 2 — une ponte d'escargots n'est pas davantage un œuf de table. */
    public function test_a_snail_lot_never_feeds_the_table_egg_stock(): void
    {
        $fiche = $this->fiche($this->bande('helico', 'ponte'), 900, 0);

        $this->assertEquals(0, app(RecordEggProductionStockAction::class)->execute($fiche));
        $this->assertEquals(0.0, (float) $this->oeufs->fresh()->stock_qty);
    }

    /**
     * ⚠️ Le mouvement porte la date de la FICHE, pas celle de la
     * synchronisation : une ponte du 3 poussée le 7 doit peser sur le stock du
     * 3, sinon le grand livre des œufs la compte au mauvais jour.
     */
    public function test_the_movement_carries_the_sheet_date_not_todays(): void
    {
        $lot = $this->bande('aviculture', 'ponte');
        $fiche = LivestockDailyEntry::create([
            'lot_id' => $lot->id,
            'entry_date' => now()->subDays(4)->toDateString(),
            'ponte_total' => 300, 'ponte_casses' => 0, 'effectif_final' => 200,
        ]);

        app(RecordEggProductionStockAction::class)->execute($fiche);

        $mouvement = StockMovement::where('reference_id', $fiche->id)->firstOrFail();
        $this->assertEquals(
            now()->subDays(4)->toDateString(),
            \Carbon\Carbon::parse($mouvement->movement_date)->toDateString(),
        );
    }

    /**
     * ⚠️⚠️ LE TEST DU DÉFAUT RÉEL : une fiche poussée depuis un poste hors
     * ligne doit incrémenter le stock, comme si elle avait été saisie à
     * l'écran. C'est ce chemin qui était mort.
     */
    public function test_a_sheet_pushed_from_a_device_increments_the_stock(): void
    {
        $lot = $this->bande('aviculture', 'ponte');
        $utilisateur = \App\Models\User::create([
            'name' => 'Animalier', 'username' => 'elevage',
            'email' => 'elevage@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        // Ticket S1 : l'envoi du poste exige désormais le rôle qui écrit chaque table.
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $utilisateur->assignRole('admin');

        $reponse = $this->actingAs($utilisateur, 'sanctum')->postJson('/api/sync/push', [
            'livestock_daily_entries' => [[
                'id' => '99999999-9999-4999-8999-999999999999',
                'lot_id' => $lot->id,
                'entry_date' => now()->toDateString(),
                'ponte_total' => 435,
                'ponte_casses' => 15,
                'effectif_final' => 200,
            ]],
        ]);

        $reponse->assertOk();
        $this->assertEquals(14.0, (float) $this->oeufs->fresh()->stock_qty,
            'une ponte saisie hors ligne doit entrer au stock comme celle saisie a l ecran');
    }

    /**
     * ⚠️ Le renvoi de la même fiche — poste qui n'a pas eu l'accusé de
     * réception — ne doit PAS compter les œufs deux fois.
     */
    public function test_pushing_the_same_sheet_twice_does_not_double_the_stock(): void
    {
        $lot = $this->bande('aviculture', 'ponte');
        $utilisateur = \App\Models\User::create([
            'name' => 'Animalier', 'username' => 'elevage',
            'email' => 'elevage@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        // Ticket S1 : l'envoi du poste exige désormais le rôle qui écrit chaque table.
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $utilisateur->assignRole('admin');

        $charge = ['livestock_daily_entries' => [[
            'id' => '99999999-9999-4999-8999-999999999999',
            'lot_id' => $lot->id,
            'entry_date' => now()->toDateString(),
            'ponte_total' => 435, 'ponte_casses' => 15, 'effectif_final' => 200,
        ]]];

        $this->actingAs($utilisateur, 'sanctum')->postJson('/api/sync/push', $charge)->assertOk();
        $this->actingAs($utilisateur, 'sanctum')->postJson('/api/sync/push', $charge)->assertOk();

        $this->assertEquals(14.0, (float) $this->oeufs->fresh()->stock_qty);
        $this->assertEquals(1, StockMovement::where('reference_type', 'daily_entry')->count());
    }

    /**
     * ⚠️ L'ÉCRAN PASSE PAR LA MÊME ACTION. La règle vivait dans
     * `FichePondeuses::saveDay()` et n'était couverte par aucun test : la
     * sortir sans vérifier le chemin d'origine aurait pu casser en silence
     * exactement ce qu'on voulait préserver.
     */
    public function test_the_livewire_screen_still_increments_the_stock(): void
    {
        $lot = $this->bande('aviculture', 'ponte');
        $utilisateur = \App\Models\User::create([
            'name' => 'Animalier', 'username' => 'elevage',
            'email' => 'elevage@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        // Ticket S1 : l'envoi du poste exige désormais le rôle qui écrit chaque table.
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $utilisateur->assignRole('admin');

        \Livewire\Livewire::actingAs($utilisateur)
            ->test(\App\Livewire\Elevage\FichePondeuses::class)
            ->set('oeufsRecoltes', 435)
            ->set('oeufsCasses', 15)
            ->call('saveDay');

        $this->assertEquals(14.0, (float) $this->oeufs->fresh()->stock_qty);
        $this->assertEquals(1, \App\Models\LivestockDailyEntry::where('lot_id', $lot->id)->count());
    }

    /**
     * ⚠️ LE CODE ESPÈCE DESCEND AVEC LA BANDE. Le poste n'a pas de table des
     * espèces : sans ce champ il ne peut pas appliquer le garde-fou
     * « aviculture + stade ponte », et devrait deviner à partir du seul stade.
     */
    public function test_the_pull_serves_the_species_code_with_each_lot(): void
    {
        $lot = $this->bande('aviculture', 'ponte');
        $utilisateur = \App\Models\User::create([
            'name' => 'Animalier', 'username' => 'elevage',
            'email' => 'elevage@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        // Ticket S1 : l'envoi du poste exige désormais le rôle qui écrit chaque table.
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $utilisateur->assignRole('admin');

        $reponse = $this->actingAs($utilisateur, 'sanctum')->getJson('/api/sync/pull');

        $reponse->assertOk();
        $bande = collect($reponse->json('livestock_lots'))
            ->firstWhere('id', $lot->id);

        $this->assertNotNull($bande);
        $this->assertEquals('aviculture', $bande['species_code']);
    }
}
