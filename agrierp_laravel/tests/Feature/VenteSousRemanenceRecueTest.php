<?php

namespace Tests\Feature;

use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Notification;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Sale;
use App\Models\User;
use App\Models\VeterinaryWithdrawalPeriod;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.68 (Sprint 14) — FILET SANITAIRE À LA RÉCEPTION.
 *
 * ⚠️⚠️ LE TROU QUE CES TESTS FERMENT. Vendre la viande d'une bande sous délai
 * d'attente expose le consommateur à des résidus d'antibiotiques. La caisse web
 * refuse cette vente, le poste aussi — mais **uniquement avec les rémanences
 * qu'il a tirées**.
 *
 * Le cas réel n'a rien d'une attaque : l'animalier traite une bande à 9 h depuis
 * le web, le poste du caissier n'a pas synchronisé depuis la veille, et à 11 h
 * il vend cette bande **en toute bonne foi**. Le serveur est alors le seul
 * endroit qui puisse s'en apercevoir — et il ne regardait pas.
 *
 * ⚠️ LA VENTE EST ENREGISTRÉE, PAS REFUSÉE : elle a déjà eu lieu. La refuser
 * retirerait des livres une recette encaissée **et** ferait perdre la
 * traçabilité de l'acheteur, seule base d'un rappel sanitaire.
 */
class VenteSousRemanenceRecueTest extends TestCase
{
    use RefreshDatabase;

    private LivestockLot $bande;

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

        $espece = LivestockSpecies::firstOrCreate(
            ['code' => 'cuniculture'],
            ['label' => 'Cuniculture', 'is_active' => true],
        );

        $this->bande = LivestockLot::create([
            'code' => 'CUN-2026-01',
            'species_id' => $espece->id,
            'stage' => 'engraissement',
            'initial_quantity' => 40,
            'current_quantity' => 40,
            'created_date' => now()->subDays(60)->toDateString(),
            'status' => 'actif',
            'is_active' => true,
        ]);

        $categorie = new ProductCategory();
        $categorie->id = '11111111-1111-4111-8111-111111111111';
        $categorie->label = 'Animaux vivants';
        $categorie->is_active = true;
        $categorie->save();

        $this->produit = Product::create([
            'sku' => 'CUN-001', 'name' => 'Lapin vivant',
            'category_id' => $categorie->id, 'species_id' => $espece->id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'tva_rate' => 0,
            'stock_qty' => 40, 'is_active' => true,
        ]);
    }

    private function remanence(string $fin): void
    {
        VeterinaryWithdrawalPeriod::create([
            'lot_id' => $this->bande->id,
            'product_used' => 'Ivermectine',
            'start_date' => now()->subDays(7)->toDateString(),
            'withdrawal_days' => 7,
            'end_date' => $fin,
        ]);
    }

    private function pousser(): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($this->utilisateur, 'sanctum')->postJson('/api/sync/push', [
            'sales' => [[
                'id' => '99999999-9999-4999-8999-999999999999',
                'payment_mode' => 'especes',
                'subtotal' => 15000,
                'total' => 15000,
                'lines' => [[
                    'product_id' => $this->produit->id,
                    'lot_id' => $this->bande->id,
                    'qty' => 3,
                    'unit_price' => 5000,
                    'manual_total_amount' => 15000,
                ]],
            ]],
        ]);
    }

    /**
     * ⚠️⚠️ LE TEST QUI COMPTE : la vente est acceptée ET l'incident signalé.
     */
    public function test_a_sale_under_withdrawal_is_recorded_and_flagged(): void
    {
        $this->remanence(now()->addDays(5)->toDateString());

        $this->pousser()->assertOk();

        // ⚠️ ENREGISTREE : la refuser retirerait des livres une recette
        // encaissee et ferait perdre l'acheteur.
        $this->assertEquals(1, Sale::count(),
            'la vente a eu lieu : la perdre empecherait tout rappel');

        // ⚠️ SIGNALEE : sinon l'incident sanitaire reste muet.
        $alerte = Notification::where('type', 'sale_under_withdrawal')->first();
        $this->assertNotNull($alerte);
        // Ticket 15.49 : `error` n'existe pas dans la colonne (MySQL strict refusait l'écriture) ; incident = critique.
        $this->assertEquals('critique', $alerte->severity);
        $this->assertStringContainsString('CUN-2026-01', $alerte->message);
        $this->assertStringContainsString('rappel', $alerte->message);
    }

    /** Une bande libre de tout délai ne déclenche aucune alerte. */
    public function test_a_clear_lot_raises_nothing(): void
    {
        $this->pousser()->assertOk();

        $this->assertEquals(1, Sale::count());
        $this->assertEquals(0, Notification::where('type', 'sale_under_withdrawal')->count());
    }

    /**
     * ⚠️ UN DÉLAI EXPIRÉ N'EST PLUS UN BLOCAGE. Alerter dessus noierait les
     * vraies alertes — et le premier réflexe devant un signal qui crie tout le
     * temps est de cesser de le lire.
     */
    public function test_an_expired_withdrawal_raises_nothing(): void
    {
        $this->remanence(now()->subDays(2)->toDateString());

        $this->pousser()->assertOk();

        $this->assertEquals(0, Notification::where('type', 'sale_under_withdrawal')->count());
    }

    /**
     * ⚠️ LE DERNIER JOUR DU DÉLAI EST ENCORE UN BLOCAGE : la viande n'est
     * consommable qu'APRÈS la fin de la période.
     */
    public function test_the_last_day_of_the_period_still_blocks(): void
    {
        $this->remanence(now()->toDateString());

        $this->pousser()->assertOk();

        $this->assertEquals(1, Notification::where('type', 'sale_under_withdrawal')->count());
    }

    /**
     * ⚠️ UNE VENTE SANS BANDE — provende, matériel — ne concerne aucune
     * rémanence et ne doit rien déclencher.
     */
    public function test_a_sale_without_a_lot_is_ignored(): void
    {
        $this->remanence(now()->addDays(5)->toDateString());

        $this->actingAs($this->utilisateur, 'sanctum')->postJson('/api/sync/push', [
            'sales' => [[
                'id' => '88888888-8888-4888-8888-888888888888',
                'payment_mode' => 'especes',
                'subtotal' => 18000,
                'total' => 18000,
                'lines' => [[
                    'product_id' => $this->produit->id,
                    'qty' => 1,
                    'unit_price' => 18000,
                    'manual_total_amount' => 18000,
                ]],
            ]],
        ])->assertOk();

        $this->assertEquals(0, Notification::where('type', 'sale_under_withdrawal')->count());
    }
}
