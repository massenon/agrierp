<?php

namespace Tests\Feature;

use App\Livewire\Stocks\GestionStocks;
use App\Models\AccountingEntry;
use App\Models\AuditLog;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\StockMovement;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket U10 — « AJOUTER STOCK » SAISI AU POSTE, REJOUÉ COMME AU WEB.
 *
 * Le poste écrit un ajout manuel dans `stock_adjustments` (`reference_type = manual_addition`). Le serveur le rejoue
 * par `AdjustStockAction` avec EXACTEMENT ce que produit `GestionStocks::submitAjouterStock()` : une entrée, datée de
 * la date choisie (pas de l'instant de réception), sans écriture comptable, avec sa trace d'audit — et il refuse ce
 * que le web refuse (quantité non entière ou < 1, sortie, date absente).
 */
class SyncAjoutStockPosteTest extends TestCase
{
    use RefreshDatabase;

    private Product $produit;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $this->admin = User::create([
            'name' => 'Administrateur', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('admin');

        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        $this->produit = Product::create([
            'sku' => 'ALI-001', 'name' => 'Provende ponte', 'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'tva_rate' => 0, 'stock_qty' => 10, 'is_active' => true,
        ]);
    }

    private function pousser(array $surcharge = []): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($this->admin, 'sanctum')->postJson('/api/sync/push', [
            'stock_adjustments' => [array_merge([
                'client_ref' => 'aaaaaaaa-0000-4000-8000-000000000001',
                'product_id' => $this->produit->id,
                'type' => 'entree',
                'quantity' => 20,
                'reference_type' => 'manual_addition',
                'reason' => null,
                'movement_date' => '2026-10-03',
            ], $surcharge)],
        ]);
    }

    public function test_l_ajout_du_poste_produit_le_meme_mouvement_que_le_web(): void
    {
        $this->travelTo('2026-10-05 15:00:00');

        $this->pousser()->assertOk()
            ->assertJsonPath('stock_adjustments.accepted.0', 'aaaaaaaa-0000-4000-8000-000000000001')
            ->assertJsonPath('stock_adjustments.rejected', []);

        // Le même ajout saisi au web, sur un second produit identique.
        $temoin = Product::create([
            'sku' => 'ALI-002', 'name' => 'Provende témoin', 'category_id' => $this->produit->category_id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'tva_rate' => 0, 'stock_qty' => 10, 'is_active' => true,
        ]);
        Livewire::actingAs($this->admin)->test(GestionStocks::class)
            ->set('addDate', '2026-10-03')->set('addProductId', $temoin->id)->set('addQty', 20)
            ->call('submitAjouterStock')->assertHasNoErrors();

        $poste = StockMovement::where('product_id', $this->produit->id)->sole();
        $web = StockMovement::where('product_id', $temoin->id)->sole();

        foreach (['type', 'reference_type', 'reason'] as $champ) {
            $this->assertSame($web->{$champ}, $poste->{$champ}, $champ);
        }
        $this->assertSame('entree', $poste->type);
        $this->assertSame('manual_addition', $poste->reference_type);
        $this->assertEquals(20.0, (float) $poste->quantity);
        // ⚠️ Daté du jour CHOISI (3 octobre), comme au web — pas du jour de réception (5 octobre).
        $this->assertSame($web->movement_date->format('Y-m-d H:i:s'), $poste->movement_date->format('Y-m-d H:i:s'));
        $this->assertSame('2026-10-03', $poste->movement_date->format('Y-m-d'));
        // La pièce porte la ligne du poste : c'est ce qui rend le renvoi inoffensif et retire la projection au poste.
        $this->assertSame('aaaaaaaa-0000-4000-8000-000000000001', $poste->reference_id);

        $this->assertEquals(30.0, (float) $this->produit->fresh()->stock_qty);
        $this->assertEquals(0, AccountingEntry::count(), 'un ajout manuel ne passe aucune écriture, au web comme ici');
        $this->assertSame(2, AuditLog::where('action', 'stock.manual_addition')->count());
    }

    public function test_un_renvoi_n_ajoute_pas_deux_fois(): void
    {
        $this->pousser()->assertOk();
        $this->pousser()->assertOk()->assertJsonPath('stock_adjustments.accepted.0', 'aaaaaaaa-0000-4000-8000-000000000001');

        $this->assertEquals(30.0, (float) $this->produit->fresh()->stock_qty);
        $this->assertSame(1, StockMovement::count());
    }

    /**
     * Les refus du web (`submitAjouterStock` : `integer`, `min:1`, date obligatoire), avec leur message français.
     */
    public function test_le_serveur_refuse_ce_que_le_web_refuse(): void
    {
        $cas = [
            'quantité non entière' => [['quantity' => 2.5], 'Le champ quantité doit être un nombre entier.'],
            'sortie' => [['type' => 'sortie'], "La valeur du champ type n'est pas autorisée."],
            'date absente' => [['movement_date' => null], 'Le champ date du mouvement est obligatoire.'],
        ];

        foreach ($cas as $nom => [$surcharge, $motif]) {
            $reponse = $this->pousser($surcharge)->assertOk();
            $this->assertSame([], $reponse->json('stock_adjustments.accepted'), $nom);
            $this->assertStringContainsString($motif, $reponse->json('stock_adjustments.rejected.0.reason'), $nom);
        }

        $this->assertEquals(10.0, (float) $this->produit->fresh()->stock_qty);
        $this->assertSame(0, StockMovement::count());
    }

    /** ⚠️ Un écart d'inventaire garde sa règle : rejoué à la réception, la date envoyée n'est pas lue. */
    public function test_un_ecart_d_inventaire_reste_date_de_sa_reception(): void
    {
        $this->travelTo('2026-10-05 15:00:00');

        $this->pousser(['reference_type' => 'inventaire', 'quantity' => 2.5])->assertOk()
            ->assertJsonPath('stock_adjustments.rejected', []);

        $this->assertSame('2026-10-05 15:00:00', StockMovement::sole()->movement_date->format('Y-m-d H:i:s'));
    }
}
