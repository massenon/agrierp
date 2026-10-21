<?php

namespace Tests\Feature;

use App\Livewire\Elevage\FicheEscargots;
use App\Livewire\Elevage\FichePondeuses;
use App\Livewire\Elevage\FicheReproducteurs;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * Ticket 15.56 — LE DON EXISTE SUR TOUTES LES FICHES, ET IL SORT DU STOCK (décision client du 17/10/2026).
 *
 * 🔴 Avant : Pondeuses, Escargots et Reproducteurs enregistraient `don = 0` en dur, sans bloc de saisie ; et une
 * fiche reçue du poste ne répercutait ni naissances, ni morts, ni dons au stock du produit de la bande.
 * Chiffres attendus calculés à la main : bande de 60, produit à 10 en stock.
 */
class DonsToutesFichesTest extends TestCase
{
    use RefreshDatabase;

    private Product $produit;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $animalier = User::create([
            'name' => 'Animalier', 'username' => 'elevage', 'email' => 'elevage@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $animalier->assignRole('animalier');
        $this->actingAs($animalier);

        $categorie = ProductCategory::create(['label' => 'Cheptel', 'is_active' => true]);
        $this->produit = Product::create([
            'sku' => 'CHE-001', 'name' => 'Sujet vivant', 'category_id' => $categorie->id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'tva_rate' => 0, 'stock_qty' => 10, 'is_active' => true,
        ]);
    }

    private function bande(string $espece, string $stade): LivestockLot
    {
        $esp = LivestockSpecies::firstOrCreate(['code' => $espece], ['label' => ucfirst($espece), 'is_enabled' => true]);
        \App\Models\ModuleConfig::updateOrCreate(['species_code' => $espece], ['is_enabled' => true]);

        return LivestockLot::create([
            'code' => 'BANDE-'.strtoupper($espece), 'species_id' => $esp->id, 'product_id' => $this->produit->id,
            'stage' => $stade, 'initial_quantity' => 60, 'current_quantity' => 60,
            'created_date' => now()->subDays(10)->toDateString(), 'status' => 'actif', 'is_active' => true,
        ]);
    }

    /** @return array<string, array{class-string, string, string, array<int, string>}> */
    public static function fiches(): array
    {
        return [
            'pondeuses' => [FichePondeuses::class, 'aviculture', 'ponte', ['donRepro', 'donPoulette', 'donPoussin']],
            'escargots' => [FicheEscargots::class, 'helico', 'engraissement', ['donBorde', 'donEngraissement', 'donNaissain']],
            'reproducteurs' => [FicheReproducteurs::class, 'aviculture', 'reproduction', ['donRepro', 'donPoulet', 'donPoussin']],
        ];
    }

    #[DataProvider('fiches')]
    public function test_les_dons_reduisent_l_effectif_et_sortent_du_stock(string $ecran, string $espece, string $stade, array $champs): void
    {
        $lot = $this->bande($espece, $stade);

        Livewire::test($ecran)
            ->set($champs[0], 2)->set($champs[2], 1)
            ->assertSee('Dons par catégorie')
            ->assertSee('Dons)')
            ->call('saveDay');

        $fiche = LivestockDailyEntry::where('lot_id', $lot->id)->sole();
        // 60 − 3 dons = 57 ; stock 10 − 3 = 7.
        $this->assertSame([3, 57], [(int) $fiche->don, (int) $fiche->effectif_final]);
        $this->assertSame(7.0, (float) $this->produit->fresh()->stock_qty);
    }

    #[DataProvider('fiches')]
    public function test_les_dons_du_jour_recharge_sont_conserves_et_comptes_une_seule_fois(string $ecran, string $espece, string $stade, array $champs): void
    {
        $lot = $this->bande($espece, $stade);
        Livewire::test($ecran)->set($champs[1], 2)->call('saveDay');

        Livewire::test($ecran)
            ->call('loadDay', now()->toDateString())
            ->assertSet('donEnregistre', 2)
            ->assertSee('2 don(s) déjà enregistré(s) ce jour')
            ->call('saveDay');

        $fiche = LivestockDailyEntry::where('lot_id', $lot->id)->sole();
        $this->assertSame([2, 58], [(int) $fiche->don, (int) $fiche->effectif_final]);
        // Calcul par ÉCART : ré-enregistrer ne retire pas une seconde fois.
        $this->assertSame(8.0, (float) $this->produit->fresh()->stock_qty);
    }

    /** 🔴 Un don saisi au POSTE sort lui aussi du stock, une seule fois même si l'envoi est répété. */
    public function test_un_don_recu_du_poste_sort_du_stock_par_ecart(): void
    {
        $lot = $this->bande('aviculture', 'reproduction');
        Sanctum::actingAs(auth()->user());
        $fiche = fn (int $don) => ['livestock_daily_entries' => [[
            'id' => '55555555-5555-4555-8555-555555555555', 'lot_id' => $lot->id,
            'entry_date' => now()->toDateString(), 'achat' => 0, 'ne' => 0, 'mort' => 1, 'vente' => 0, 'don' => $don,
        ]]];

        $this->postJson('/api/sync/push', $fiche(2))->assertOk()->assertJsonPath('livestock_daily_entries.accepted.0', '55555555-5555-4555-8555-555555555555');
        $this->assertSame(7.0, (float) $this->produit->fresh()->stock_qty, '10 − 1 mort − 2 dons');

        $this->postJson('/api/sync/push', $fiche(2))->assertOk();
        $this->assertSame(7.0, (float) $this->produit->fresh()->stock_qty, 'renvoi identique : aucun mouvement');

        $this->postJson('/api/sync/push', $fiche(4))->assertOk();
        $this->assertSame(5.0, (float) $this->produit->fresh()->stock_qty, 'correction : seul l\'écart de 2 sort');
        $this->assertSame(55, (int) LivestockDailyEntry::sole()->effectif_final);
    }
}
