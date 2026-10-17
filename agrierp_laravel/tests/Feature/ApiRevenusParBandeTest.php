<?php

namespace Tests\Feature;

use App\Models\CreditNote;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\User;
use App\Services\LotRevenueService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 15.12 — le revenu par bande descend au poste (`lot_revenues`), calculé
 * par le service que la page web utilise aussi : un seul chiffre.
 */
class ApiRevenusParBandeTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private LivestockLot $bandeA;

    private LivestockLot $bandeB;

    private Product $poulet;

    protected function setUp(): void
    {
        parent::setUp();

        Role::findOrCreate('animalier', 'web');
        $user = User::create([
            'name' => 'Animalier', 'username' => 'animal', 'email' => 'animal@olouwachegoun.bj',
            'password' => bcrypt(self::MDP), 'is_active' => true,
        ]);
        $user->assignRole('animalier');

        $espece = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'AVI', 'is_active' => true]);

        $this->bandeA = $this->bande($espece, 'AVI-2026-001');
        $this->bandeB = $this->bande($espece, 'AVI-2026-002');

        $this->poulet = Product::create([
            'sku' => 'AVI-P01', 'name' => 'Poulet vif',
            'category_id' => ProductCategory::create(['label' => 'Volailles', 'is_active' => true])->id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 3_000, 'price_max' => 4_000,
            'tva_rate' => 0, 'stock_qty' => 60, 'is_active' => true,
        ]);
    }

    private function bande(LivestockSpecies $espece, string $code): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code, 'species_id' => $espece->id, 'stage' => 'croissance',
            'initial_quantity' => 100, 'current_quantity' => 80,
            'created_date' => '2026-01-15', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    private function vendre(LivestockLot $lot, float $montant, string $statut = 'validee'): Sale
    {
        $vente = Sale::create([
            'payment_mode' => 'especes', 'subtotal' => $montant, 'discount' => 0,
            'total' => $montant, 'status' => $statut,
        ]);

        SaleLine::create([
            'sale_id' => $vente->id, 'product_id' => $this->poulet->id, 'lot_id' => $lot->id,
            'qty' => 1, 'unit_price' => $montant, 'manual_total_amount' => $montant,
            'is_manual_price' => true,
        ]);

        return $vente;
    }

    private function tirage(): array
    {
        $jeton = $this->postJson('/api/auth/login', [
            'identifiant' => 'animal', 'password' => self::MDP, 'device_name' => 'poste-01',
        ])->json('token');

        return $this->withHeader('Authorization', 'Bearer '.$jeton)
            ->getJson('/api/sync/pull')->assertOk()->json('lot_revenues');
    }

    public function test_le_tirage_sert_une_ligne_par_bande_et_par_produit(): void
    {
        $this->vendre($this->bandeA, 45_000);
        $this->vendre($this->bandeA, 15_000);
        $this->vendre($this->bandeB, 99_000);

        $lignes = collect($this->tirage());

        $a = $lignes->firstWhere('lot_id', $this->bandeA->id);
        $b = $lignes->firstWhere('lot_id', $this->bandeB->id);

        $this->assertCount(2, $lignes);
        $this->assertEquals(60_000, $a['amount']);
        $this->assertEquals(99_000, $b['amount']);
        $this->assertSame('Ventes — Poulet vif', $a['label']);
        $this->assertSame($this->poulet->id, $a['product_id']);
    }

    public function test_une_vente_annulee_n_est_pas_un_revenu(): void
    {
        $this->vendre($this->bandeA, 45_000);
        $this->vendre($this->bandeA, 30_000, 'annulee');

        $this->assertEquals(45_000, $this->tirage()[0]['amount']);
    }

    public function test_un_avoir_traite_est_deduit_et_un_avoir_en_attente_ne_bouge_rien(): void
    {
        $vente = $this->vendre($this->bandeA, 45_000);

        CreditNote::create([
            'credit_note_number' => 'AV-0001', 'sale_id' => $vente->id, 'product_id' => $this->poulet->id,
            'qty' => 2, 'amount' => 6_000, 'reason' => 'Malade', 'decision' => 'reforme', 'status' => 'traite',
        ]);
        CreditNote::create([
            'credit_note_number' => 'AV-0002', 'sale_id' => $vente->id, 'product_id' => $this->poulet->id,
            'qty' => 1, 'amount' => 3_000, 'reason' => 'En cours', 'status' => 'en_attente',
        ]);

        $this->assertEquals(39_000, $this->tirage()[0]['amount']);
    }

    public function test_le_tirage_et_la_page_web_servent_le_meme_chiffre(): void
    {
        $this->vendre($this->bandeA, 45_000);

        $service = app(LotRevenueService::class);

        $this->assertEquals(
            $service->forLot($this->bandeA->id)[0]['montant'],
            $this->tirage()[0]['amount'],
        );
    }

    public function test_une_vente_sans_bande_n_est_imputee_a_personne(): void
    {
        $vente = Sale::create([
            'payment_mode' => 'especes', 'subtotal' => 10_000, 'discount' => 0,
            'total' => 10_000, 'status' => 'validee',
        ]);
        SaleLine::create([
            'sale_id' => $vente->id, 'product_id' => $this->poulet->id, 'lot_id' => null,
            'qty' => 1, 'unit_price' => 10_000, 'manual_total_amount' => 10_000, 'is_manual_price' => true,
        ]);

        $this->assertSame([], $this->tirage());
    }

    public function test_aucune_vente_donne_une_liste_vide_et_non_une_erreur(): void
    {
        $this->assertSame([], $this->tirage());
    }

    public function test_un_envoi_de_revenus_par_le_poste_est_ignore(): void
    {
        $jeton = $this->postJson('/api/auth/login', [
            'identifiant' => 'animal', 'password' => self::MDP, 'device_name' => 'poste-01',
        ])->json('token');

        $reponse = $this->withHeader('Authorization', 'Bearer '.$jeton)
            ->postJson('/api/sync/push', ['lot_revenues' => [['lot_id' => 'x', 'amount' => 1]]])
            ->assertOk();

        $this->assertGreaterThanOrEqual(1, $reponse->json('referentiels_ignored'));
    }
}
