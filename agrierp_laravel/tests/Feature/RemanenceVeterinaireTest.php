<?php

namespace Tests\Feature;

use App\Livewire\Ventes\PosInterface;
use App\Models\FiscalYear;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\Sale;
use App\Models\User;
use App\Models\VeterinaryWithdrawalPeriod;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.21 (Sprint 14) — BLOCAGE DE VENTE SOUS RÉMANENCE VÉTÉRINAIRE.
 *
 * Règle de sécurité alimentaire : un sujet issu d'une bande encore sous délai
 * d'attente après traitement vétérinaire ne doit pas pouvoir être vendu. Le
 * CDC la qualifie de « blocage réel, côté serveur, jamais contournable en
 * modifiant le DOM ou en désactivant le JavaScript » (Document 00 §7).
 *
 * ⚠️ CETTE RÈGLE N'AVAIT AUCUN TEST — ni Feature, ni Dusk vert. Le parcours
 * navigateur correspondant est rouge depuis toujours. Aucune preuve
 * n'existait donc que le blocage fonctionne.
 *
 * L'enjeu dépasse le logiciel : vendre la viande ou les œufs d'un animal
 * encore sous traitement engage la responsabilité de la ferme.
 */
class RemanenceVeterinaireTest extends TestCase
{
    use RefreshDatabase;

    private LivestockLot $lot;

    private Product $sujet;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-ventes', 'manage-ventes'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('caissier', 'web');
        $role->givePermissionTo(['view-ventes', 'manage-ventes']);

        $user = User::create([
            'name' => 'Caissière',
            'email' => 'caisse.remanence@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'),
        ]);
        $user->assignRole($role);
        $this->actingAs($user);

        FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);

        $species = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);

        $this->lot = LivestockLot::create([
            'code' => 'LOT-LAP-TRAITE',
            'species_id' => $species->id,
            'stage' => 'engraissement',
            'initial_quantity' => 30,
            'current_quantity' => 30,
            'created_date' => now()->subMonth()->format('Y-m-d'),
            'status' => 'actif',
            'is_active' => true,
        ]);

        $categorie = ProductCategory::create(['label' => 'Sujets vivants', 'is_active' => true]);

        $this->sujet = Product::create([
            'sku' => 'LAP-VIF',
            'name' => 'Lapin vif',
            'category_id' => $categorie->id,
            'unit' => 'pièce',
            'pricing_mode' => 'fourchette',
            'price_min' => 3000,
            'price_max' => 5000,
            'stock_qty' => 30,
            'species_id' => $species->id,
            'is_active' => true,
        ]);
    }

    private function declarerRemanence(int $joursRestants = 5): VeterinaryWithdrawalPeriod
    {
        return VeterinaryWithdrawalPeriod::create([
            'lot_id' => $this->lot->id,
            'product_used' => 'Antibiotique VHD',
            'start_date' => now()->subDays(2)->format('Y-m-d'),
            'withdrawal_days' => 7,
            'end_date' => now()->addDays($joursRestants)->format('Y-m-d'),
        ]);
    }

    private function lignePanier(int $qty = 2, float $montant = 8000): array
    {
        return [[
            'product_id' => $this->sujet->id,
            'name' => $this->sujet->name,
            'unit' => $this->sujet->unit,
            'lot_id' => $this->lot->id,
            'lot_code' => $this->lot->code,
            'qty' => $qty,
            'montant' => $montant,
        ]];
    }

    /** Garde-fou existant : l'ajout au panier est bien refusé. */
    public function test_adding_a_blocked_subject_to_the_cart_is_refused(): void
    {
        $this->declarerRemanence();

        Livewire::test(PosInterface::class)
            ->set('weightProductId', $this->sujet->id)
            ->set('weightLotId', $this->lot->id)
            ->set('weightQty', 2)
            ->set('weightPrice', 8000)
            ->call('confirmWeightAdd');

        $this->assertSame([], Livewire::test(PosInterface::class)->instance()->cart);
    }

    /**
     * LE TEST QUI COMPTE — CONTOURNEMENT RÉEL.
     *
     * `cart` est une propriété PUBLIQUE Livewire, donc alimentée depuis la
     * requête du client. Un panier peut donc arriver directement à
     * `validateSale()` sans jamais passer par `confirmWeightAdd()`, c'est-à-dire
     * sans jamais rencontrer le contrôle de rémanence. C'est exactement le
     * scénario que le CDC exige de bloquer : « jamais contournable en modifiant
     * le DOM ou en désactivant le JavaScript ».
     */
    public function test_the_block_cannot_be_bypassed_by_submitting_the_cart_directly(): void
    {
        $this->declarerRemanence();

        Livewire::test(PosInterface::class)
            ->set('cart', $this->lignePanier())          // panier injecté, sans passer par la modale
            ->set('paymentMode', 'especes')
            ->set('cashReceived', 8000)
            ->call('validateSale');

        $this->assertEquals(
            0,
            Sale::count(),
            "Une vente d'un sujet sous rémanence ne doit JAMAIS être enregistrée, même si le panier contourne la modale."
        );
        $this->assertEquals(
            30,
            (float) $this->sujet->fresh()->stock_qty,
            'Le stock ne doit pas bouger si la vente est refusée.'
        );
    }

    /**
     * Rémanence déclarée APRÈS la mise au panier : au moment de valider, le
     * sujet est sous traitement. La vente doit être refusée — le contrôle doit
     * porter sur l'instant de la vente, pas sur celui de la mise au panier.
     */
    public function test_a_withdrawal_declared_after_adding_to_cart_still_blocks_the_sale(): void
    {
        $composant = Livewire::test(PosInterface::class)
            ->set('cart', $this->lignePanier())
            ->set('paymentMode', 'especes')
            ->set('cashReceived', 8000);

        $this->declarerRemanence();   // le vétérinaire intervient entre-temps

        $composant->call('validateSale');

        $this->assertEquals(0, Sale::count());
    }

    /** Une rémanence ÉCHUE ne doit rien bloquer. */
    public function test_an_expired_withdrawal_no_longer_blocks(): void
    {
        VeterinaryWithdrawalPeriod::create([
            'lot_id' => $this->lot->id,
            'product_used' => 'Antibiotique VHD',
            'start_date' => now()->subDays(20)->format('Y-m-d'),
            'withdrawal_days' => 7,
            'end_date' => now()->subDay()->format('Y-m-d'),   // terminée hier
        ]);

        Livewire::test(PosInterface::class)
            ->set('cart', $this->lignePanier())
            ->set('paymentMode', 'especes')
            ->set('cashReceived', 8000)
            ->call('validateSale');

        $this->assertEquals(1, Sale::count(), 'Une rémanence échue ne doit plus bloquer la vente.');
    }

    /** Une bande non traitée se vend normalement — le blocage ne sur-bloque pas. */
    public function test_a_lot_without_withdrawal_sells_normally(): void
    {
        Livewire::test(PosInterface::class)
            ->set('cart', $this->lignePanier())
            ->set('paymentMode', 'especes')
            ->set('cashReceived', 8000)
            ->call('validateSale');

        $this->assertEquals(1, Sale::count());
        $this->assertEquals(28, (float) $this->sujet->fresh()->stock_qty);
    }
}
