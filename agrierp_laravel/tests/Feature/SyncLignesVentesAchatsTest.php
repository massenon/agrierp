<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseLine;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\Supplier;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket U4 (décision D-U4 du 19/10/2026) — LES LIGNES DES VENTES ET DES ACHATS DESCENDENT AU POSTE.
 *
 * Le Tableau de bord du poste calculait le Top 5 des produits (marge « — ») et les ventes porcines sur les seules
 * lignes saisies SUR LE POSTE : `sale_lines` et `purchase_lines` ne descendaient pas, alors que les ventes et les
 * achats, eux, descendaient. Le web calcule sur toutes les ventes — deux chiffres pour la même ferme.
 *
 * Ce que ces tests verrouillent :
 *  - le tirage sert les lignes des pièces servies, avec les colonnes que le poste absorbe ;
 *  - AU MÊME CURSEUR que leur pièce : une pièce modifiée renvoie TOUTES ses lignes (le poste les remplace), une
 *    ligne modifiée seule fait redescendre sa pièce ;
 *  - AUCUNE FUITE : jamais une ligne d'une pièce non servie (le poste la refuserait, pièce inconnue).
 */
class SyncLignesVentesAchatsTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    private Supplier $fournisseur;

    private Product $porc;

    private Product $provende;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->utilisateur = User::create([
            'name' => 'Administrateur', 'username' => 'admin',
            'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->utilisateur->assignRole('admin');

        $categorie = ProductCategory::create(['label' => 'Porciculture', 'is_active' => true]);
        $this->porc = Product::create([
            'sku' => 'POR-CHA', 'name' => 'Porc charcutier', 'category_id' => $categorie->id, 'unit' => 'tête',
            'pricing_mode' => 'fourchette', 'price_min' => 10000, 'price_max' => 90000,
            'stock_qty' => 10, 'is_active' => true,
        ]);
        $this->provende = Product::create([
            'sku' => 'ALI-PONTE', 'name' => 'Provende ponte', 'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'price_min' => 8000, 'price_max' => 8000,
            'stock_qty' => 10, 'is_active' => true,
        ]);
        $this->fournisseur = Supplier::create([
            'name' => 'Provenderie du Plateau', 'category' => 'Aliments', 'is_active' => true,
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function vente(array $lignes): Sale
    {
        $total = array_sum(array_column($lignes, 1));
        $vente = Sale::create([
            'payment_mode' => 'especes', 'subtotal' => $total, 'total' => $total, 'status' => 'validee',
        ]);
        foreach ($lignes as [$qte, $montant]) {
            SaleLine::create([
                'sale_id' => $vente->id, 'product_id' => $this->porc->id, 'qty' => $qte,
                'unit_price' => round($montant / $qte, 2), 'manual_total_amount' => $montant,
                'is_manual_price' => true,
            ]);
        }

        return $vente;
    }

    private function achat(array $lignes): Purchase
    {
        $achat = Purchase::create([
            'supplier_id' => $this->fournisseur->id, 'payment_mode' => 'especes',
            'total' => array_sum(array_map(fn ($l) => $l[0] * $l[1], $lignes)),
            'purchase_date' => now()->format('Y-m-d'),
        ]);
        foreach ($lignes as [$qte, $prix]) {
            PurchaseLine::create([
                'purchase_id' => $achat->id, 'product_id' => $this->provende->id, 'qty' => $qte, 'unit_price' => $prix,
            ]);
        }

        return $achat;
    }

    private function tirer(?string $depuis = null)
    {
        return $this->actingAs($this->utilisateur, 'sanctum')
            ->getJson('/api/sync/pull'.($depuis ? '?since='.urlencode($depuis) : ''))
            ->assertOk();
    }

    /** Aucune ligne servie n'appartient à une pièce non servie. */
    private function sansFuite($reponse): void
    {
        $ventes = collect($reponse->json('sales'))->pluck('id');
        $achats = collect($reponse->json('purchases'))->pluck('id');
        foreach ($reponse->json('sale_lines') as $ligne) {
            $this->assertTrue($ventes->contains($ligne['sale_id']), 'ligne de vente servie sans sa vente');
        }
        foreach ($reponse->json('purchase_lines') as $ligne) {
            $this->assertTrue($achats->contains($ligne['purchase_id']), "ligne d'achat servie sans son achat");
        }
    }

    public function test_le_tirage_complet_sert_les_lignes_des_ventes_et_des_achats(): void
    {
        $vente = $this->vente([[1, 30000], [2.5, 40000]]);
        $achat = $this->achat([[10, 8000], [5, 8200]]);

        $reponse = $this->tirer();

        $lignes = collect($reponse->json('sale_lines'))->where('sale_id', $vente->id)->values();
        $this->assertCount(2, $lignes);
        $ligne = $lignes->firstWhere('qty', 2.5);
        // `manual_total_amount` fait foi ; `unit_price` est servi tel que stocké (dérivé).
        $this->assertEquals(40000, $ligne['manual_total_amount']);
        $this->assertEquals(16000, $ligne['unit_price']);
        $this->assertSame($this->porc->id, $ligne['product_id']);
        $this->assertArrayHasKey('lot_id', $ligne);
        $this->assertNotEmpty($ligne['id']);

        $lignesAchat = collect($reponse->json('purchase_lines'))->where('purchase_id', $achat->id)->values();
        $this->assertCount(2, $lignesAchat);
        $this->assertEquals(8200, $lignesAchat->firstWhere('qty', 5)['unit_price']);
        $this->assertSame('Provende ponte', $lignesAchat->first()['product_name']);
        $this->sansFuite($reponse);
    }

    public function test_le_tirage_incremental_ne_sert_que_les_lignes_des_pieces_servies(): void
    {
        Carbon::setTestNow('2026-10-19 08:00:00');
        $ancienneVente = $this->vente([[1, 30000]]);
        $ancienAchat = $this->achat([[4, 8000]]);
        $depuis = '2026-10-19T09:00:00';

        Carbon::setTestNow('2026-10-19 10:00:00');
        $nouvelleVente = $this->vente([[3, 90000]]);
        $nouvelAchat = $this->achat([[2, 8100]]);

        $reponse = $this->tirer($depuis);

        $this->assertEquals([$nouvelleVente->id], collect($reponse->json('sales'))->pluck('id')->all());
        $this->assertEquals([$nouvelleVente->id], collect($reponse->json('sale_lines'))->pluck('sale_id')->all());
        $this->assertEquals([$nouvelAchat->id], collect($reponse->json('purchase_lines'))->pluck('purchase_id')->all());
        // Pas de fuite : les lignes des pièces antérieures au curseur ne redescendent pas.
        $this->assertNotContains($ancienneVente->id, collect($reponse->json('sale_lines'))->pluck('sale_id'));
        $this->assertNotContains($ancienAchat->id, collect($reponse->json('purchase_lines'))->pluck('purchase_id'));
        $this->sansFuite($reponse);
    }

    public function test_une_piece_modifiee_renvoie_toutes_ses_lignes(): void
    {
        Carbon::setTestNow('2026-10-19 08:00:00');
        $vente = $this->vente([[1, 30000], [2, 50000]]);
        $achat = $this->achat([[4, 8000], [6, 7900]]);
        $depuis = '2026-10-19T09:00:00';

        // La pièce change APRÈS le curseur (ex. statut MeCeF d'une vente, retour d'un achat), pas ses lignes.
        Carbon::setTestNow('2026-10-19 10:00:00');
        $vente->update(['mecef_status' => 'transmise']);
        $achat->forceFill(['returned_at' => now()])->save();

        $reponse = $this->tirer($depuis);

        $this->assertCount(2, collect($reponse->json('sale_lines'))->where('sale_id', $vente->id));
        $this->assertCount(2, collect($reponse->json('purchase_lines'))->where('purchase_id', $achat->id));
        $this->sansFuite($reponse);
    }

    public function test_une_ligne_modifiee_seule_fait_redescendre_sa_piece_et_toutes_ses_lignes(): void
    {
        Carbon::setTestNow('2026-10-19 08:00:00');
        $vente = $this->vente([[1, 30000], [2, 50000]]);
        $achat = $this->achat([[4, 8000], [6, 7900]]);
        $depuis = '2026-10-19T09:00:00';

        Carbon::setTestNow('2026-10-19 10:00:00');
        SaleLine::where('sale_id', $vente->id)->first()->touch();
        PurchaseLine::where('purchase_id', $achat->id)->first()->touch();

        $reponse = $this->tirer($depuis);

        $this->assertEquals([$vente->id], collect($reponse->json('sales'))->pluck('id')->all());
        $this->assertCount(2, collect($reponse->json('sale_lines'))->where('sale_id', $vente->id));
        $this->assertEquals([$achat->id], collect($reponse->json('purchases'))->pluck('id')->all());
        $this->assertCount(2, collect($reponse->json('purchase_lines'))->where('purchase_id', $achat->id));
        $this->sansFuite($reponse);
    }

    public function test_sans_rien_de_nouveau_aucune_ligne_ne_descend(): void
    {
        Carbon::setTestNow('2026-10-19 08:00:00');
        $this->vente([[1, 30000]]);
        $this->achat([[4, 8000]]);

        $reponse = $this->tirer('2026-10-19T09:00:00');

        $this->assertSame([], $reponse->json('sale_lines'));
        $this->assertSame([], $reponse->json('purchase_lines'));
    }
}
