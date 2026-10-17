<?php

namespace Tests\Feature;

use App\Livewire\Stocks\GestionStocks;
use App\Livewire\Ventes\ProfileClient;
use App\Models\Customer;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Receivable;
use App\Models\Role;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.3 — suite du balayage systématique ouvert au ticket 14.2.
 *
 * Sur les 15 candidats détectés, 5 composants portaient un défaut RÉEL et 8
 * étaient des faux positifs (analyse au cas par cas, jamais un patch en lot).
 * Deux sous-motifs distincts, couverts ici par un test chacun :
 *
 *  A. « lire puis `reset()` » — la propriété dérive d'un état public que
 *     l'action réinitialise (`GestionStocks::validateAdjustment`, et de même
 *     `EnregistrerAchat::submitAchat`, `TransformationForm::validateTransformation`,
 *     déjà prouvé sur `PosInterface::validateSale` au ticket 14.2).
 *
 *  B. « collection filtrée puis mutation » — la propriété est une requête qui
 *     EXCLUT les lignes soldées ; les solder ne les retire pas de la
 *     collection déjà en cache (`ProfileClient::confirmRegularisation`, et de
 *     même `ProfileFournisseur::confirmRegularisation`).
 */
class StaleComputedPropertiesTest extends TestCase
{
    use RefreshDatabase;

    private function actingAsAdmin(array $permissions): User
    {
        foreach ($permissions as $name) {
            Permission::findOrCreate($name, 'web');
        }
        $role = Role::findOrCreate('admin', 'web');
        $role->givePermissionTo($permissions);

        $user = User::create([
            'name' => 'Admin Test',
            'email' => 'dg.test@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'),
        ]);
        $user->assignRole($role);
        $this->actingAs($user);

        return $user;
    }

    private function treasury(): TreasuryAccount
    {
        return TreasuryAccount::create([
            'type' => 'caisse',
            'label' => 'Caisse Principale',
            'account_code' => '531',
            'balance' => 0,
            'is_active' => true,
        ]);
    }

    /**
     * Motif B — une créance intégralement réglée doit disparaître de la liste
     * des créances ouvertes, et le solde global suivre, sans rafraîchissement.
     */
    public function test_a_fully_settled_receivable_leaves_the_open_list_immediately(): void
    {
        $this->actingAsAdmin(['view-ventes', 'manage-ventes']);

        $customer = Customer::create([
            'name' => 'GBAGUIDI Solange',   // client de référence du projet
            'phone' => '+22997000000',
            'is_active' => true,
        ]);

        Receivable::create([
            'customer_id' => $customer->id,
            'amount' => 50_000,
            'amount_paid' => 0,
            'due_date' => now()->subDays(10)->format('Y-m-d'),
            'status' => 'en_cours',
        ]);
        Receivable::create([
            'customer_id' => $customer->id,
            'amount' => 30_000,
            'amount_paid' => 0,
            'due_date' => now()->subDays(2)->format('Y-m-d'),
            'status' => 'en_cours',
        ]);

        $component = Livewire::test(ProfileClient::class, ['customer' => $customer]);

        $this->assertCount(2, $component->instance()->receivables);
        $this->assertEquals(80_000.0, $component->instance()->soldeGlobal);

        // Règlement global FIFO : solde intégralement la plus ancienne (50 000)
        // et laisse 30 000 sur la seconde.
        $component
            ->set('regularisationTarget', '')
            ->set('regularisationMontant', 50_000)
            ->set('regularisationTreasuryId', $this->treasury()->id)
            ->call('confirmRegularisation');

        // L'état réel en base : une seule créance encore ouverte.
        $this->assertEquals(1, Receivable::whereColumn('amount_paid', '<', 'amount')->count());

        // …et l'écran doit le refléter immédiatement.
        $this->assertCount(1, $component->instance()->receivables, 'La créance soldée doit quitter la liste des créances ouvertes.');
        $this->assertEquals(30_000.0, $component->instance()->soldeGlobal, 'Le solde global doit suivre le règlement.');
    }

    /**
     * Motif A — après un ajustement d'inventaire, le panneau doit repartir
     * vide et non réafficher le produit et l'écart déjà traités.
     */
    public function test_adjustment_panel_resets_after_a_validated_adjustment(): void
    {
        $this->actingAsAdmin(['view-stocks', 'manage-stocks']);

        $category = ProductCategory::create(['label' => 'Provende', 'is_active' => true]);
        $product = Product::create([
            'sku' => 'ALI-001',
            'name' => 'Aliment ponte',
            'category_id' => $category->id,
            'unit' => 'kg',
            'pricing_mode' => 'fourchette',
            'price_min' => 500,
            'price_max' => 700,
            'stock_qty' => 100,
            'is_active' => true,
        ]);

        $component = Livewire::test(GestionStocks::class)
            ->set('adjProductId', $product->id)
            ->set('adjPhysical', 92);

        // Écart constaté avant validation : -8 kg.
        $this->assertEquals(-8.0, $component->instance()->adjDiff);

        $component->set('adjReason', 'Casse constatée')->call('validateAdjustment');

        // Le stock réel a bien bougé…
        $this->assertEquals(92.0, (float) $product->fresh()->stock_qty);

        // …et le panneau est réellement revenu à zéro.
        $this->assertSame('', $component->instance()->adjProductId);
        $this->assertNull($component->instance()->adjSelectedProduct, 'Aucun produit ne doit rester sélectionné après validation.');
        $this->assertEquals(0.0, $component->instance()->adjDiff, "L'écart affiché doit repartir de zéro après validation.");
    }
}
