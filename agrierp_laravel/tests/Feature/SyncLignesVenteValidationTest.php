<?php

namespace Tests\Feature;

use App\Models\Expense;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Sale;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.70 (Sprint 14) — LE CONTENU DES LIGNES DE VENTE.
 *
 * ⚠️⚠️ Les lignes étaient créées par **assignation de masse** —
 * `SaleLine::create(array_merge(['sale_id' => …], $line))` — sans le moindre
 * contrôle. Trois conséquences :
 *
 * 1. un `product_id` inexistant levait une violation de clé étrangère **non
 *    rattrapée** : 500 pour la requête ENTIÈRE, emportant les fiches d'élevage
 *    et les dépenses du même envoi ;
 * 2. une quantité nulle ou négative passait, alors qu'une vente à quantité
 *    négative ferait **remonter** le stock ;
 * 3. un `total` incohérent avec les lignes produisait une écriture
 *    **équilibrée et fausse** : `RecordSaleAccountingEntryAction` remet les
 *    lignes à l'échelle du total annoncé — juste pour une remise, désastreux
 *    pour un total erroné.
 */
class SyncLignesVenteValidationTest extends TestCase
{
    use RefreshDatabase;

    private Product $produit;

    private User $utilisateur;

    protected function setUp(): void
    {
        parent::setUp();

        $this->utilisateur = User::create([
            'name' => 'Caissier', 'username' => 'caisse',
            'email' => 'caisse@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);

        // Ticket S1 : l'envoi du poste exige désormais le rôle qui écrit chaque table.

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $this->utilisateur->assignRole('admin');

        $categorie = new ProductCategory();
        $categorie->id = '11111111-1111-4111-8111-111111111111';
        $categorie->label = 'Aliments';
        $categorie->is_active = true;
        $categorie->save();

        $this->produit = Product::create([
            'sku' => 'ALI-001', 'name' => 'Provende ponte',
            'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'tva_rate' => 0,
            'stock_qty' => 50, 'is_active' => true,
        ]);
    }

    private function pousser(array $remplacements = []): \Illuminate\Testing\TestResponse
    {
        $vente = array_merge([
            'id' => '99999999-9999-4999-8999-999999999999',
            'payment_mode' => 'especes',
            'subtotal' => 18000,
            'discount' => 0,
            'total' => 18000,
            'lines' => [[
                'product_id' => $this->produit->id,
                'qty' => 1,
                'unit_price' => 18000,
                'manual_total_amount' => 18000,
            ]],
        ], $remplacements);

        return $this->actingAs($this->utilisateur, 'sanctum')
            ->postJson('/api/sync/push', ['sales' => [$vente]]);
    }

    /**
     * ⚠️⚠️ LE DÉFAUT LE PLUS COÛTEUX : un produit inconnu faisait tomber TOUT
     * l'envoi. Ici la vente est refusée seule, et la dépense du même envoi
     * passe.
     */
    public function test_an_unknown_product_rejects_only_that_sale(): void
    {
        $caisse = TreasuryAccount::create([
            'label' => 'Caisse Physique', 'account_code' => '531',
            'type' => 'caisse', 'balance' => 500000, 'is_active' => true,
        ]);

        $reponse = $this->actingAs($this->utilisateur, 'sanctum')->postJson('/api/sync/push', [
            'sales' => [[
                'id' => '99999999-9999-4999-8999-999999999999',
                'payment_mode' => 'especes',
                'subtotal' => 18000, 'discount' => 0, 'total' => 18000,
                'lines' => [[
                    'product_id' => '00000000-0000-4000-8000-000000000000',
                    'qty' => 1, 'unit_price' => 18000,
                    'manual_total_amount' => 18000,
                ]],
            ]],
            'expenses' => [[
                'id' => '22222222-2222-4222-8222-222222222222',
                'expense_date' => now()->toDateString(),
                'label' => 'Gasoil groupe',
                'category' => '605 - Énergie',
                'amount' => 12000,
                'treasury_account_id' => $caisse->id,
            ]],
        ]);

        // ⚠️ 200, pas 500 : une vente fautive n'emporte pas le reste.
        $reponse->assertOk();
        $reponse->assertJsonPath('sales.accepted', []);
        $this->assertEquals(0, Sale::count());

        $this->assertEquals(1, Expense::count(),
            'une vente refusee ne doit pas faire perdre une depense du meme envoi');
    }

    /**
     * ⚠️ UNE QUANTITÉ NÉGATIVE FERAIT REMONTER LE STOCK sur une vente.
     */
    public function test_a_negative_quantity_is_refused(): void
    {
        $this->pousser(['lines' => [[
            'product_id' => $this->produit->id,
            'qty' => -3,
            'unit_price' => 18000,
            'manual_total_amount' => 18000,
        ]]])->assertOk();

        $this->assertEquals(0, Sale::count());
        $this->assertEquals(50.0, (float) $this->produit->fresh()->stock_qty);
    }

    /** Une quantité nulle n'est pas davantage une vente. */
    public function test_a_zero_quantity_is_refused(): void
    {
        $this->pousser(['lines' => [[
            'product_id' => $this->produit->id,
            'qty' => 0,
            'unit_price' => 18000,
            'manual_total_amount' => 18000,
        ]]])->assertOk();

        $this->assertEquals(0, Sale::count());
    }

    /**
     * ⚠️ LE MONTANT DE LIGNE EST OBLIGATOIRE : c'est la source de vérité du
     * prix (Document 01 §6.7) et la colonne est NOT NULL — son absence levait
     * une violation de contrainte, donc un 500 global.
     */
    public function test_a_line_without_its_amount_is_refused(): void
    {
        $this->pousser(['lines' => [[
            'product_id' => $this->produit->id,
            'qty' => 1,
            'unit_price' => 18000,
        ]]])->assertOk();

        $this->assertEquals(0, Sale::count());
    }

    /**
     * ⚠️⚠️ UN TOTAL INCOHÉRENT PRODUISAIT UNE ÉCRITURE ÉQUILIBRÉE ET FAUSSE.
     * L'Action remet les lignes à l'échelle du total annoncé — juste pour une
     * remise, désastreux pour un total erroné. Le contrôle est donc à la porte.
     */
    public function test_an_incoherent_total_is_refused(): void
    {
        $reponse = $this->pousser(['total' => 999999]);

        $reponse->assertOk();
        $this->assertEquals(0, Sale::count());
        $this->assertStringContainsString(
            'incoherent',
            strtolower($reponse->json('sales.rejected.0.reason')),
        );
    }

    /**
     * ⚠️ UNE REMISE RESTE LÉGITIME : total = lignes − remise. Refuser ce cas
     * casserait la caisse pour de bon.
     */
    public function test_a_discount_remains_accepted(): void
    {
        $this->pousser(['discount' => 3000, 'total' => 15000])->assertOk();

        $this->assertEquals(1, Sale::count());
    }

    /**
     * ⚠️ TOLÉRANCE D'UN CENTIME : les montants transitent en flottants depuis
     * un client Dart. L'égalité stricte ferait rejeter des ventes saines.
     */
    public function test_a_rounding_difference_of_one_cent_passes(): void
    {
        $this->pousser(['total' => 18000.004])->assertOk();

        $this->assertEquals(1, Sale::count());
    }

    /** Le flux nominal reste accepté. */
    public function test_a_valid_sale_is_still_accepted(): void
    {
        $this->pousser()->assertOk();

        $this->assertEquals(1, Sale::count());
        $this->assertEquals(49.0, (float) $this->produit->fresh()->stock_qty);
    }
}
