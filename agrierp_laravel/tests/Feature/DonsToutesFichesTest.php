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
            'password' => bcrypt('LogiAgriERP@2026'), 'is_active' => true,
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
            'escargots' => [FicheEscargots::class, 'helico', 'engraissement', ['donBorde', 'donEngraissement', 'donNaissain']],
            // VOL-1 / VOL-2 : les fiches Reproducteurs et Pondeuses ont un départ obligatoire et des dons ventilés rechargés par
            // catégorie ou par stade : leurs dons sont couverts par `test_reproducteurs_*` et `test_pondeuses_*` ci-dessous et par
            // VolaillesEffectifParCategorieTest / PondeusesEffectifParStadeTest.
        ];
    }

    /** VOL-1 — dons de la fiche Reproducteurs : ventilés, réduisent l'effectif et sortent du stock, une seule fois. */
    public function test_reproducteurs_les_dons_ventiles_reduisent_l_effectif_sortent_du_stock_et_se_rechargent(): void
    {
        $lot = $this->bande('aviculture', 'reproduction');

        Livewire::test(FicheReproducteurs::class)
            ->set('departRepro', 40)->set('departJeune', 15)->set('departSevre', 5)
            ->set('donRepro', 2)->set('donPoussin', 1)
            ->assertSee('Dons par catégorie')
            ->call('saveDay');

        $fiche = LivestockDailyEntry::where('lot_id', $lot->id)->sole();
        // 60 − 3 dons = 57 ; stock 10 − 3 = 7 ; catégories 38 / 15 / 4.
        $this->assertSame([3, 57], [(int) $fiche->don, (int) $fiche->effectif_final]);
        $this->assertSame([2, 1, 0], [(int) $fiche->don_repro, (int) $fiche->don_sevre, (int) $fiche->don_jeune]);
        $this->assertSame([38, 15, 4], [(int) $fiche->cat_eff_repro, (int) $fiche->cat_eff_jeune, (int) $fiche->cat_eff_sevre]);
        $this->assertSame(7.0, (float) $this->produit->fresh()->stock_qty);

        Livewire::test(FicheReproducteurs::class)
            ->call('loadDay', now()->toDateString())
            ->assertSet('donRepro', 2)->assertSet('donPoussin', 1)->assertSet('donPoulet', 0)->assertSet('donEnregistre', null)
            ->call('saveDay');
        $this->assertSame(7.0, (float) $this->produit->fresh()->stock_qty, 'calcul par écart : rien ne sort deux fois');
    }

    /** VOL-2 — dons de la fiche Pondeuses : ventilés par stade, réduisent l'effectif et sortent du stock, une seule fois. */
    public function test_pondeuses_les_dons_ventiles_reduisent_l_effectif_sortent_du_stock_et_se_rechargent(): void
    {
        $lot = $this->bande('aviculture', 'ponte');

        Livewire::test(FichePondeuses::class)
            ->set('departPondeuse', 40)->set('departPoulette', 10)->set('departPoussinCroissance', 6)->set('departPoussinPonte', 4)
            ->set('donPondeuse', 2)->set('donPoussinPonte', 1)
            ->assertSee('Dons par catégorie')
            ->call('saveDay');

        $fiche = LivestockDailyEntry::where('lot_id', $lot->id)->sole();
        // 60 − 3 dons = 57 ; stock 10 − 3 = 7 ; stades PP 3 / PC 6 / PL 10 / PO 38.
        $this->assertSame([3, 57], [(int) $fiche->don, (int) $fiche->effectif_final]);
        $this->assertSame([2, 1, 0, 0], [(int) $fiche->don_repro, (int) $fiche->don_4, (int) $fiche->don_sevre, (int) $fiche->don_jeune]);
        $this->assertSame([3, 6, 10, 38], [(int) $fiche->cat_eff_4, (int) $fiche->cat_eff_sevre, (int) $fiche->cat_eff_jeune, (int) $fiche->cat_eff_repro]);
        $this->assertSame(7.0, (float) $this->produit->fresh()->stock_qty);

        Livewire::test(FichePondeuses::class)
            ->call('loadDay', now()->toDateString())
            ->assertSet('donPondeuse', 2)->assertSet('donPoussinPonte', 1)->assertSet('donPoulette', 0)->assertSet('donEnregistre', null)
            ->call('saveDay');
        $this->assertSame(7.0, (float) $this->produit->fresh()->stock_qty, 'calcul par écart : rien ne sort deux fois');
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
        $lot = $this->bande('aviculture', 'ponte');
        Sanctum::actingAs(auth()->user());
        // VOL-2 : la fiche d'une bande de pondeuses porte son départ par stade (tous « Pondeuse ») et sa ventilation ; le don
        // (2 puis 4) est rangé dans les Pondeuses.
        $fiche = fn (int $don) => ['livestock_daily_entries' => [[
            'id' => '55555555-5555-4555-8555-555555555555', 'lot_id' => $lot->id,
            'entry_date' => now()->toDateString(), 'achat' => 0, 'ne' => 0, 'mort' => 1, 'vente' => 0, 'don' => $don,
            'cat_depart_repro' => 60, 'cat_depart_sevre' => 0, 'cat_depart_jeune' => 0, 'cat_depart_4' => 0,
            'mort_repro' => 1, 'mort_sevre' => 0, 'mort_jeune' => 0, 'mort_4' => 0,
            'don_repro' => $don, 'don_sevre' => 0, 'don_jeune' => 0, 'don_4' => 0,
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
