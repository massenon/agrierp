<?php

namespace Tests\Feature;

use App\Livewire\Elevage\BilanTechnicoEconomique;
use App\Models\CreditNote;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\Transformation;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.44 (Sprint 14) — REVENUS PAR BANDE au Bilan Technico-Économique.
 *
 * La carte « Revenu Total du Lot » affichait « — / Sprint 4 (Ventes) » alors
 * que le POS existe depuis le Sprint 4. Le vrai maillon manquant était
 * ailleurs : `sale_lines` ne conservait PAS la bande vendue, pourtant connue
 * du panier au moment de la vente.
 *
 * Le test qui compte le plus est le dernier : quand une bande a été
 * transformée, son revenu est PROUVÉ incomplet — la marge doit être minorée
 * et l'écran doit le dire, jamais laisser croire à un verdict complet.
 */
class BilanTechnicoEconomiqueRevenusTest extends TestCase
{
    use RefreshDatabase;

    private LivestockLot $bande;

    private Product $poulet;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('admin', 'web');
        $role->givePermissionTo(['view-elevage', 'manage-elevage']);

        $user = User::create([
            'name' => 'Animalier', 'email' => 'elevage@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $user->assignRole($role);
        $this->actingAs($user);

        $espece = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'AVI', 'is_active' => true]);

        $this->bande = LivestockLot::create([
            'code' => 'AVI-2026-001', 'species_id' => $espece->id, 'stage' => 'croissance',
            'initial_quantity' => 100, 'current_quantity' => 60,
            'created_date' => '2026-01-15', 'acquisition_cost' => 200_000,
            'status' => 'actif', 'is_active' => true,
        ]);

        $categorie = ProductCategory::create(['label' => 'Volailles', 'is_active' => true]);

        $this->poulet = Product::create([
            'sku' => 'AVI-P01', 'name' => 'Poulet vif', 'category_id' => $categorie->id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 3_000, 'price_max' => 4_000,
            'tva_rate' => 0, 'stock_qty' => 60, 'is_active' => true,
        ]);
    }

    private function vendre(float $montant, int $qty = 1, string $statut = 'validee', ?string $lotId = null): Sale
    {
        $vente = Sale::create([
            'payment_mode' => 'especes', 'subtotal' => $montant, 'discount' => 0,
            'total' => $montant, 'status' => $statut,
        ]);

        SaleLine::create([
            'sale_id' => $vente->id, 'product_id' => $this->poulet->id,
            'lot_id' => $lotId ?? $this->bande->id,
            'qty' => $qty, 'unit_price' => $qty > 0 ? $montant / $qty : 0,
            'manual_total_amount' => $montant, 'is_manual_price' => true,
        ]);

        return $vente;
    }

    private function bilan(): BilanTechnicoEconomique
    {
        return Livewire::test(BilanTechnicoEconomique::class)
            ->set('lotId', $this->bande->id)
            ->instance();
    }

    /** LE MAILLON MANQUANT : la vente est imputée à la bande réellement vendue. */
    public function test_a_sale_feeds_the_revenue_of_its_own_lot(): void
    {
        $this->vendre(45_000, 15);

        $bilan = $this->bilan();

        $this->assertEquals(45_000, $bilan->revenuTotalConnu);
        $this->assertEquals('Ventes — Poulet vif', $bilan->revenus[0]['label']);
    }

    /** Une vente d'une AUTRE bande ne pollue pas ce bilan. */
    public function test_a_sale_from_another_lot_does_not_leak(): void
    {
        $autre = LivestockLot::create([
            'code' => 'AVI-2026-002', 'species_id' => $this->bande->species_id, 'stage' => 'croissance',
            'initial_quantity' => 50, 'current_quantity' => 50,
            'created_date' => '2026-02-01', 'status' => 'actif', 'is_active' => true,
        ]);

        $this->vendre(45_000, 15);
        $this->vendre(99_000, 30, 'validee', $autre->id);

        $this->assertEquals(45_000, $this->bilan()->revenuTotalConnu);
    }

    /** ⚠️ Une vente annulée n'est pas un revenu. */
    public function test_a_cancelled_sale_is_not_revenue(): void
    {
        $this->vendre(45_000, 15);
        $this->vendre(30_000, 10, 'annulee');

        $this->assertEquals(45_000, $this->bilan()->revenuTotalConnu);
    }

    /** ⚠️ Un avoir traité vient EN DÉDUCTION : un retour n'est pas un revenu. */
    public function test_a_processed_credit_note_is_deducted(): void
    {
        $vente = $this->vendre(45_000, 15);

        CreditNote::create([
            'credit_note_number' => 'AV-0001', 'sale_id' => $vente->id,
            'product_id' => $this->poulet->id, 'qty' => 2, 'amount' => 6_000,
            'reason' => 'Sujet malade', 'decision' => 'reforme', 'status' => 'traite',
        ]);

        $this->assertEquals(39_000, $this->bilan()->revenuTotalConnu);
    }

    /** Un avoir non encore traité ne bouge rien. */
    public function test_an_untreated_credit_note_changes_nothing(): void
    {
        $vente = $this->vendre(45_000, 15);

        CreditNote::create([
            'credit_note_number' => 'AV-0002', 'sale_id' => $vente->id,
            'product_id' => $this->poulet->id, 'qty' => 2, 'amount' => 6_000,
            'reason' => 'En cours', 'status' => 'en_attente',
        ]);

        $this->assertEquals(45_000, $this->bilan()->revenuTotalConnu);
    }

    /** La marge se calcule enfin — revenus connus moins coûts connus. */
    public function test_the_net_margin_is_finally_computable(): void
    {
        $this->vendre(450_000, 60);

        $bilan = $this->bilan();

        // Coût connu = acquisition 200 000 (provende et véto nuls ici).
        $this->assertEquals(200_000, $bilan->coutTotalConnu);
        $this->assertEquals(250_000, $bilan->margeNette);
    }

    /**
     * ⚠️ LE CAS QUI COMPTE, ET QUI A CORRIGÉ UNE AFFIRMATION FAUSSE.
     *
     * Ce ticket a d'abord déclaré le revenu des produits transformés « non
     * rattachable — stock fongible ». C'était faux pour CETTE application :
     * le POS exige la bande source pour tout produit lié à une espèce,
     * transformés compris, et le caissier la désigne à la caisse. Le lien
     * n'est pas reconstruit après coup, il est SAISI — donc exact.
     */
    public function test_transformed_product_revenue_belongs_to_its_lot(): void
    {
        $viande = Product::create([
            'sku' => 'AVI-P05', 'name' => 'Poulet fumé', 'category_id' => $this->poulet->category_id,
            'species_id' => $this->bande->species_id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 5_000, 'price_max' => 6_000,
            'tva_rate' => 0, 'stock_qty' => 14, 'is_active' => true,
        ]);

        Transformation::create([
            'lot_id' => $this->bande->id, 'product_id' => $viande->id,
            'qty_animals' => 10, 'qty_produced' => 14,
            'transformation_date' => '2026-06-01',
            'operator_id' => auth()->id(),
        ]);

        // Vente du produit fini, imputée à la bande comme le POS l'impose.
        $vente = Sale::create([
            'payment_mode' => 'especes', 'subtotal' => 70_000, 'discount' => 0,
            'total' => 70_000, 'status' => 'validee',
        ]);
        SaleLine::create([
            'sale_id' => $vente->id, 'product_id' => $viande->id, 'lot_id' => $this->bande->id,
            'qty' => 14, 'unit_price' => 5_000, 'manual_total_amount' => 70_000, 'is_manual_price' => true,
        ]);

        $this->vendre(45_000, 15);

        $bilan = $this->bilan();

        $this->assertEquals(115_000, $bilan->revenuTotalConnu,
            'Le transforme compte dans le revenu de sa bande, au meme titre que le sujet vif.');
        $this->assertNotNull(
            collect($bilan->revenus)->firstWhere('label', 'Ventes — Poulet fumé')
        );
    }

    /**
     * L'onglet « Bilan » du Tableau de Bord Élevage affiche le MÊME calcul,
     * par imbrication du composant — jamais un second coût de revient recopié
     * qui finirait par diverger.
     */
    public function test_the_elevage_dashboard_tab_shows_the_same_figures(): void
    {
        $this->vendre(45_000, 15);

        Livewire::test(\App\Livewire\Elevage\DashboardElevage::class)
            ->set('tab', 'bilan')
            ->assertSeeLivewire(BilanTechnicoEconomique::class)
            ->assertDontSee('Sprint 5 (Achats)');
    }

    /**
     * 🔴 La main d'œuvre reste en attente, mais le motif a changé : ce n'est
     * plus la paie qui manque, c'est la clé d'imputation.
     */
    public function test_labour_is_still_pending_for_the_right_reason(): void
    {
        $mainDoeuvre = collect($this->bilan()->couts)->firstWhere('label', "Main d'œuvre imputée");

        $this->assertFalse($mainDoeuvre['reel']);
        $this->assertStringContainsString("clé d'imputation", $mainDoeuvre['motif']);
        $this->assertStringNotContainsString('Sprint 8', $mainDoeuvre['motif']);
    }
}
