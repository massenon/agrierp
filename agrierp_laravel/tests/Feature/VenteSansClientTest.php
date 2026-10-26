<?php

namespace Tests\Feature;

use App\Livewire\Ventes\PosInterface;
use App\Models\ChartOfAccount;
use App\Models\Customer;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Receivable;
use App\Models\Role;
use App\Models\Sale;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket VTE-1 — « Je n'arrive pas à enregistrer de ventes » : la règle du client à la caisse, au web ET à l'envoi du poste.
 *
 *  1. Une vente au COMPTANT s'enregistre TOUJOURS sans client (« Client Anonyme »).
 *  2. Une vente à CRÉDIT ou « Déduire de l'avance » exige un client connu : sans lui, la créance (ou l'avance) n'aurait
 *     aucun propriétaire. Refus MOTIVÉ, jamais silencieux, rien d'écrit.
 *  3. Au serveur, un client inconnu (le client du poste a été refusé, ou n'est jamais parti) ne rejette PAS l'envoi entier :
 *     refus motivé de CETTE vente, lisible (« client … inconnu du serveur »), relançable après l'envoi du client. Un client
 *     créé au poste part AVANT ses ventes, dans le même envoi.
 */
class VenteSansClientTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private Product $produit;

    private string $token;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-ventes', 'manage-ventes'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('caissier', 'web');
        $role->givePermissionTo(['view-ventes', 'manage-ventes']);

        $user = User::create(['name' => 'Caissière', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com', 'password' => bcrypt(self::MDP), 'is_active' => true]);
        $user->assignRole($role);
        $this->actingAs($user);

        FiscalYear::create(['year' => now()->year, 'start_date' => now()->startOfYear()->format('Y-m-d'), 'end_date' => now()->endOfYear()->format('Y-m-d'), 'status' => 'ouvert']);
        foreach ([['531', 'Caisse', 5], ['411', 'Clients', 4], ['701', 'Ventes', 7]] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);

        $categorie = ProductCategory::create(['label' => 'Aviculture', 'is_active' => true]);
        $this->produit = Product::create([
            'sku' => 'AVI-001', 'name' => 'Oeufs', 'category_id' => $categorie->id, 'unit' => 'u',
            'pricing_mode' => 'fourchette', 'price_min' => 1_000, 'price_max' => 8_000, 'tva_rate' => 0, 'stock_qty' => 50, 'is_active' => true,
        ]);

        $this->token = $this->postJson('/api/auth/login', [
            'identifiant' => 'caisse', 'password' => self::MDP, 'device_name' => 'poste-ferme-01',
        ])->json('token');
    }

    private function caisse(string $mode, string $clientId = '')
    {
        return Livewire::test(PosInterface::class)
            ->set('paymentMode', $mode)
            ->set('customerId', $clientId)
            ->set('cart', [[
                'product_id' => $this->produit->id, 'name' => 'Oeufs', 'unit' => 'u',
                'qty' => 2, 'montant' => 6_000, 'lot_id' => null, 'lot_code' => null,
            ]])
            ->call('validateSale');
    }

    private function pousser(array $corps)
    {
        return $this->withHeader('Authorization', 'Bearer '.$this->token)->postJson('/api/sync/push', $corps);
    }

    private function vente(string $id, array $remplacements = []): array
    {
        return array_merge([
            'id' => $id, 'payment_mode' => 'especes', 'subtotal' => 6_000, 'discount' => 0, 'total' => 6_000, 'status' => 'validee',
            'lines' => [['product_id' => $this->produit->id, 'qty' => 2, 'unit_price' => 3_000, 'manual_total_amount' => 6_000]],
        ], $remplacements);
    }

    // ── Web ──────────────────────────────────────────────────────────────────────────────────────

    public function test_web_une_vente_au_comptant_s_enregistre_sans_client(): void
    {
        $this->caisse('especes');

        $this->assertSame(1, Sale::count());
        $this->assertNull(Sale::first()->customer_id);
    }

    public function test_web_une_vente_a_credit_sans_client_est_refusee_avec_son_motif(): void
    {
        $this->caisse('credit')
            ->assertHasErrors(['customerId'])
            ->assertDispatched('toast', message: 'Une vente à crédit exige un client : choisissez-le dans la liste ou créez-le avec le bouton « + ».', type: 'error');

        $this->assertSame(0, Sale::count());
        $this->assertSame(0, Receivable::count());
    }

    public function test_web_une_vente_sur_avance_sans_client_est_refusee(): void
    {
        $this->caisse('avance')->assertHasErrors(['customerId']);

        $this->assertSame(0, Sale::count());
    }

    public function test_web_une_vente_a_credit_avec_client_cree_sa_creance(): void
    {
        $client = Customer::create(['name' => 'Revendeur', 'is_active' => true]);

        $this->caisse('credit', $client->id)->assertHasNoErrors();

        $this->assertSame(1, Sale::count());
        $this->assertEquals(6_000, (float) Receivable::where('customer_id', $client->id)->value('amount'));
    }

    // ── Envoi du poste ───────────────────────────────────────────────────────────────────────────

    public function test_envoi_une_vente_au_comptant_sans_client_est_acceptee(): void
    {
        $this->pousser(['sales' => [$this->vente('11111111-1111-4111-8111-111111111111')]])
            ->assertOk()
            ->assertJsonPath('sales.accepted.0', '11111111-1111-4111-8111-111111111111');
    }

    public function test_envoi_une_vente_a_credit_sans_client_est_refusee_sans_bloquer_les_autres(): void
    {
        $credit = '22222222-2222-4222-8222-222222222222';
        $comptant = '33333333-3333-4333-8333-333333333333';

        $reponse = $this->pousser(['sales' => [$this->vente($credit, ['payment_mode' => 'credit']), $this->vente($comptant)]])->assertOk();

        $reponse->assertJsonPath('sales.accepted', [$comptant]);
        $reponse->assertJsonPath('sales.rejected.0.id', $credit);
        $this->assertSame('Une vente à crédit exige un client.', $reponse->json('sales.rejected.0.reason'));
        $this->assertNull(Sale::find($credit));
        $this->assertSame(0, Receivable::count());
    }

    public function test_envoi_un_client_inconnu_du_serveur_est_un_refus_motive_et_relancable(): void
    {
        $inconnu = 'cccccccc-0000-4000-8000-000000000009';
        $id = '44444444-4444-4444-8444-444444444444';
        $autre = '55555555-5555-4555-8555-555555555555';

        $reponse = $this->pousser(['sales' => [$this->vente($id, ['customer_id' => $inconnu]), $this->vente($autre)]])->assertOk();

        $reponse->assertJsonPath('sales.accepted', [$autre]);
        $this->assertSame($id, $reponse->json('sales.rejected.0.id'));
        $this->assertSame(
            "Client inconnu du serveur : cette vente porte un client qui n'a pas encore été envoyé (ou qu'il a refusé). Envoyez d'abord le client, puis relancez la vente.",
            $reponse->json('sales.rejected.0.reason'),
        );
        $this->assertNull(Sale::find($id));

        // Le client arrive, la vente relancée passe.
        $this->pousser(['customers' => [['id' => $inconnu, 'name' => 'GBAGUIDI Solange']], 'sales' => [$this->vente($id, ['customer_id' => $inconnu])]])
            ->assertOk()
            ->assertJsonPath('sales.accepted', [$id]);
        $this->assertSame($inconnu, Sale::find($id)->customer_id);
    }

    public function test_envoi_un_client_cree_au_poste_part_avant_sa_vente_a_credit_dans_le_meme_envoi(): void
    {
        $client = 'dddddddd-0000-4000-8000-000000000001';
        $id = '66666666-6666-4666-8666-666666666666';

        $this->pousser([
            // Les ventes sont écrites AVANT les clients dans le JSON : seul l'ordre de traitement du serveur compte.
            'sales' => [$this->vente($id, ['customer_id' => $client, 'payment_mode' => 'credit'])],
            'customers' => [['id' => $client, 'name' => 'GBAGUIDI Solange']],
        ])->assertOk()->assertJsonPath('sales.accepted', [$id])->assertJsonPath('customers.accepted', [$client]);

        $this->assertEquals(6_000, (float) Receivable::where('sale_id', $id)->value('amount'));
    }
}
