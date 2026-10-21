<?php

namespace Tests\Feature;

use App\Livewire\Elevage\FicheEscargots;
use App\Livewire\Elevage\FichePorcs;
use App\Livewire\Elevage\TransformationForm;
use App\Livewire\Ventes\PosInterface;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\ModuleConfig;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\Mecef\MecefGatewayInterface;
use App\Services\TransactionRejouable;
use App\Support\OrdreDesVerrous;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket U14 — PREUVE DE L'ORDRE DES VERROUS : le stock (`products`) AVANT la fiche (`livestock_daily_entries`) et la
 * bande (`livestock_lots`), dans l'envoi des postes ET dans chaque composant web qui touche les deux (caisse, fiches,
 * Transformation). Voir `App\Support\OrdreDesVerrous`.
 *
 * ⚠️ SQLite (cette suite) n'a pas de `FOR UPDATE` : la preuve se lit dans le JOURNAL DES REQUÊTES. Pour chaque geste :
 *  1. la requête de verrouillage du stock (`select "id" from "products" where "id" in (…) order by "id" asc`) passe
 *     AVANT la première écriture d'une fiche ou d'une bande ;
 *  2. chaque produit dont le stock est ensuite écrit (`update "products" set "stock_qty"`) figure dans ce verrou.
 * Deux transactions qui suivent cette règle ne peuvent plus s'attendre en croix (stock contre fiche) : la seconde se met
 * en file sur le stock avant d'avoir touché la moindre fiche. Sous MariaDB, l'essai à plusieurs postes en fait la
 * preuve en charge réelle (`agrierp_flutter/outils/essai_multipostes.sh`).
 */
class OrdreDesVerrousTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private Product $poulet;

    private Product $produitDeBande;

    private LivestockLot $bande;

    /** @var array<int, array{sql: string, bindings: array}> */
    private array $requetes = [];

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-14 12:00:00');
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->admin = User::create([
            'name' => 'Direction', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('admin');
        $this->actingAs($this->admin);

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        foreach ([['411', 'Clients', 4], ['531', 'Caisse', 5], ['701', 'Ventes de marchandises', 7], ['443', 'TVA collectée', 4]] as [$code, $libelle, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $libelle, 'class' => $classe, 'is_active' => true]);
        }
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);

        $espece = LivestockSpecies::create(['label' => 'Porcs', 'code' => 'porciculture', 'is_enabled' => true]);
        $categorie = ProductCategory::create(['label' => 'Élevage', 'is_active' => true]);
        $produit = fn (string $sku, string $nom) => Product::create([
            'sku' => $sku, 'name' => $nom, 'category_id' => $categorie->id, 'species_id' => $espece->id, 'unit' => 'u',
            'pricing_mode' => 'fourchette', 'price_min' => 3_000, 'price_max' => 90_000, 'tva_rate' => 0, 'stock_qty' => 50,
            'is_active' => true,
        ]);
        // Identifiants fixés pour que l'ordre croissant se voie : le produit de la bande est le PLUS PETIT.
        $this->produitDeBande = $produit('POR-VIF', 'Porcelet vif');
        $this->poulet = $produit('POR-CAR', 'Carcasse de porc');
        $this->bande = LivestockLot::create([
            'code' => 'POR-A', 'species_id' => $espece->id, 'stage' => 'engraissement', 'product_id' => $this->produitDeBande->id,
            'initial_quantity' => 40, 'current_quantity' => 40, 'created_date' => '2026-10-01', 'status' => 'actif', 'is_active' => true,
        ]);

        $this->app->instance(TransactionRejouable::class, new TransactionRejouable(DB::transactionLevel()));
        $this->app->instance(MecefGatewayInterface::class, new class implements MecefGatewayInterface
        {
            public function transmit(\App\Models\Sale $sale): array
            {
                return ['success' => true, 'qr_ref' => 'NIM-ESSAI', 'message' => 'Facture transmise (essai).'];
            }
        });
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function ecouter(): void
    {
        $this->requetes = [];
        DB::listen(function ($q) {
            $this->requetes[] = ['sql' => $q->sql, 'bindings' => $q->bindings];
        });
    }

    /** Vérifie la règle sur les requêtes du geste ; rend les produits verrouillés. */
    private function assertStockAvantFiche(string $geste): array
    {
        $verrou = null;
        $premiereFiche = null;
        $stockEcrit = [];
        foreach ($this->requetes as $i => $q) {
            if ($verrou === null && preg_match('/^select "id" from "products" where "id" in \(.*\) order by "id" asc$/', $q['sql'])) {
                $verrou = $i;
            }
            if ($premiereFiche === null && preg_match('/^(insert into|update) "(livestock_daily_entries|livestock_lots)"/', $q['sql'])) {
                $premiereFiche = $i;
            }
            if (str_starts_with($q['sql'], 'update "products" set "stock_qty"')) {
                $stockEcrit[] = end($q['bindings']);
            }
        }

        $this->assertNotNull($verrou, "$geste : aucun verrouillage du stock");
        $this->assertNotNull($premiereFiche, "$geste : aucune fiche écrite (le geste n'a pas eu lieu)");
        $this->assertLessThan($premiereFiche, $verrou, "$geste : une fiche est écrite AVANT le verrouillage du stock");
        $verrouilles = $this->requetes[$verrou]['bindings'];
        $this->assertSame($verrouilles, collect($verrouilles)->sort()->values()->all(), "$geste : par identifiant croissant");
        foreach ($stockEcrit as $id) {
            $this->assertContains($id, $verrouilles, "$geste : stock du produit $id écrit sans avoir été verrouillé d'abord");
        }

        return $verrouilles;
    }

    public function test_envoi_d_un_poste_fiche_et_vente_le_stock_d_abord(): void
    {
        Sanctum::actingAs($this->admin);
        $this->ecouter();

        $this->postJson('/api/sync/push', [
            'livestock_daily_entries' => [[
                'id' => '55555555-5555-4555-8555-555555555555', 'lot_id' => $this->bande->id,
                'entry_date' => '2026-10-14', 'achat' => 0, 'ne' => 3, 'mort' => 1, 'vente' => 0, 'don' => 0,
            ]],
            'sales' => [[
                'id' => '66666666-6666-4666-8666-666666666666', 'payment_mode' => 'especes', 'subtotal' => 9_000,
                'discount' => 0, 'total' => 9_000, 'status' => 'validee',
                'lines' => [['product_id' => $this->poulet->id, 'lot_id' => $this->bande->id, 'qty' => 2, 'unit_price' => 4_500, 'manual_total_amount' => 9_000]],
            ]],
        ])->assertOk()
            ->assertJsonPath('livestock_daily_entries.accepted.0', '55555555-5555-4555-8555-555555555555')
            ->assertJsonPath('sales.accepted.0', '66666666-6666-4666-8666-666666666666');

        $verrouilles = $this->assertStockAvantFiche('envoi du poste');
        $this->assertEqualsCanonicalizing([$this->produitDeBande->id, $this->poulet->id], $verrouilles);
    }

    public function test_caisse_du_web_le_stock_du_panier_d_abord(): void
    {
        $caisse = Livewire::test(PosInterface::class)
            ->call('selectProduct', $this->poulet->id)
            ->set('weightQty', 2)
            ->set('weightPrice', 9_000)
            ->set('weightLotId', $this->bande->id)
            ->call('confirmWeightAdd')
            ->set('paymentMode', 'especes')
            ->set('cashReceived', 9_000);
        $this->ecouter();

        $caisse->call('validateSale');

        $this->assertContains($this->poulet->id, $this->assertStockAvantFiche('caisse du web'));
    }

    public function test_fiche_porcs_le_stock_de_la_bande_d_abord(): void
    {
        $fiche = Livewire::test(FichePorcs::class)->set('ne', 3);
        $this->ecouter();

        $fiche->call('saveDay')->assertHasNoErrors();

        $this->assertSame([$this->produitDeBande->id], $this->assertStockAvantFiche('fiche Porcs'));
        $this->assertEquals(53, (float) $this->produitDeBande->fresh()->stock_qty, '3 naissances au stock');
    }

    public function test_fiche_escargots_en_une_transaction_le_stock_d_abord(): void
    {
        ModuleConfig::create(['species_code' => 'helico', 'is_enabled' => true]);
        $helico = LivestockSpecies::create(['label' => 'Escargots', 'code' => 'helico', 'is_enabled' => true]);
        $this->bande->update(['species_id' => $helico->id]);
        $fiche = Livewire::test(FicheEscargots::class)->set('naissainsNes', 4);
        $this->ecouter();

        $fiche->call('saveDay')->assertHasNoErrors();

        $this->assertSame([$this->produitDeBande->id], $this->assertStockAvantFiche('fiche Escargots'));
    }

    public function test_transformation_le_produit_fini_d_abord(): void
    {
        $forme = Livewire::test(TransformationForm::class)
            ->set('lotId', $this->bande->id)
            ->set('qtyAnimals', 2)
            ->set('productId', $this->poulet->id)
            ->set('qtyProduced', 2)
            ->set('transformationDate', '2026-10-14');
        $this->ecouter();

        $forme->call('validateTransformation')->assertHasNoErrors();

        $this->assertContains($this->poulet->id, $this->assertStockAvantFiche('Transformation'));
    }

    /**
     * Garde-fou lu dans le code : TOUT composant Livewire qui écrit une fiche ET mouvemente le stock verrouille le stock
     * (`OrdreDesVerrous::stock`) avant sa première écriture de fiche — y compris un composant ajouté demain.
     */
    public function test_tout_composant_qui_touche_stock_et_fiche_verrouille_le_stock_d_abord(): void
    {
        $verifies = [];
        foreach (glob(app_path('Livewire/*/*.php')) as $fichier) {
            $source = (string) file_get_contents($fichier);
            $stock = preg_match('/(AdjustStockAction|SyncLotProductionStockAction|RecordEggProductionStockAction)::class\)->execute/', $source);
            $fiche = preg_match('/LivestockDailyEntry::updateOrCreate|RecordSaleOnFicheElevageAction::class\)->execute/', $source, $m, PREG_OFFSET_CAPTURE);
            if (! $stock || ! $fiche) {
                continue;
            }
            $verrou = strpos($source, 'OrdreDesVerrous::stock(');
            $this->assertNotFalse($verrou, basename($fichier).' : stock et fiche sans `OrdreDesVerrous::stock`');
            $this->assertLessThan($m[0][1], $verrou, basename($fichier).' : la fiche est écrite avant le verrou du stock');
            $verifies[] = basename($fichier, '.php');
        }

        // Témoins : les sept composants connus au ticket U14.
        $this->assertEqualsCanonicalizing(
            ['FicheEscargots', 'FicheLapins', 'FichePondeuses', 'FichePorcs', 'FicheReproducteurs', 'TransformationForm', 'PosInterface'],
            $verifies,
        );
    }

    public function test_hors_transaction_rien_n_est_verrouille(): void
    {
        DB::rollBack();   // sort de la transaction de RefreshDatabase le temps du constat
        try {
            $this->ecouter();
            OrdreDesVerrous::stock([$this->poulet->id]);
            $this->assertSame([], $this->requetes, 'un verrou hors transaction ne protège rien : aucune requête');
        } finally {
            DB::beginTransaction();
        }
    }
}
