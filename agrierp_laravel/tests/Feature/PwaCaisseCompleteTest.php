<?php

namespace Tests\Feature;

use App\Models\Customer;
use App\Models\Sale;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Feature\Concerns\AvecEmecef;
use Tests\TestCase;

/**
 * PWA-1b — LE SERVEUR REÇOIT LA CAISSE COMPLÈTE DU NAVIGATEUR : livraison facturée dans le total, vente sur avance, client créé hors
 * ligne puis vente de ce client (idempotence par UUID du navigateur). Le serveur reste juge : il recalcule les frais et le drapeau.
 */
class PwaCaisseCompleteTest extends TestCase
{
    use AvecEmecef;
    use RefreshDatabase;

    private const SALE = 'f1111111-1111-4111-8111-111111111111';

    private const CLIENT = 'f2222222-2222-4222-8222-222222222222';

    protected function setUp(): void
    {
        parent::setUp();
        $this->decorVentes();
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);
    }

    /** @return array<string, mixed> */
    private function vente(array $plus = []): array
    {
        return array_merge([
            'id' => self::SALE, 'payment_mode' => 'especes', 'status' => 'validee', 'subtotal' => 11800, 'discount' => 0, 'total' => 11800,
            'sold_at' => now()->subMinute()->toDateTimeString(),
            'lines' => [['product_id' => $this->taxable->id, 'qty' => 2, 'unit_price' => 5900, 'manual_total_amount' => 11800]],
        ], $plus);
    }

    private function pousser(array $corps)
    {
        return $this->actingAs(User::first(), 'sanctum')->postJson('/api/sync/push', $corps);
    }

    public function test_une_livraison_facturee_entre_dans_le_total_et_le_serveur_pose_le_drapeau(): void
    {
        $r = $this->pousser(['sales' => [$this->vente([
            'total' => 14300, 'delivery_mode' => 'facturee', 'delivery_fee' => 2500, 'delivery_address' => 'Pobè, route de Kétou', 'delivery_contact' => '0197000000',
            'delivery_in_total' => false, // jamais lu : le serveur le recalcule
        ])]]);

        $this->assertSame([self::SALE], $r->json('sales.accepted'));
        $v = Sale::findOrFail(self::SALE);
        $this->assertSame('facturee', $v->delivery_mode);
        $this->assertSame('2500.00', $v->delivery_fee);
        $this->assertTrue($v->delivery_in_total);
        $this->assertSame('Pobè, route de Kétou', $v->delivery_address);
        $this->assertSame('0197000000', $v->delivery_contact);
    }

    public function test_un_total_sans_la_livraison_facturee_est_refuse_avec_le_motif_du_total(): void
    {
        $r = $this->pousser(['sales' => [$this->vente(['delivery_mode' => 'facturee', 'delivery_fee' => 2500])]]);

        $this->assertSame([], $r->json('sales.accepted'));
        $this->assertStringContainsString('Total incoherent : 11800 annonce, 14300 attendu', $r->json('sales.rejected.0.reason'));
        $this->assertSame(0, Sale::count());
    }

    public function test_les_autres_modes_de_livraison_n_ajoutent_aucun_frais(): void
    {
        foreach (['gratuite', 'client', 'incluse'] as $i => $mode) {
            $id = 'f3333333-3333-4333-8333-33333333333'.$i;
            $r = $this->pousser(['sales' => [$this->vente(['id' => $id, 'delivery_mode' => $mode, 'delivery_fee' => 9999])]]);
            $this->assertSame([$id], $r->json('sales.accepted'), $mode);
            $v = Sale::findOrFail($id);
            $this->assertSame('0.00', $v->delivery_fee, "$mode : les frais saisis sont ignorés");
            $this->assertFalse($v->delivery_in_total);
            $this->assertSame($mode, $v->delivery_mode);
        }
    }

    public function test_une_livraison_invalide_est_refusee_avec_son_motif_et_un_poste_sans_livraison_ne_change_pas(): void
    {
        $r = $this->pousser(['sales' => [$this->vente(['delivery_mode' => 'drone'])]]);
        $this->assertSame("La valeur du champ mode de livraison n'est pas autorisée.", $r->json('sales.rejected.0.reason'));

        $r = $this->pousser(['sales' => [$this->vente(['delivery_mode' => 'facturee', 'delivery_fee' => -5, 'total' => 11800])]]);
        $this->assertStringContainsString('frais de livraison', $r->json('sales.rejected.0.reason'));

        $r = $this->pousser(['sales' => [$this->vente(['delivery_address' => str_repeat('A', 256), 'delivery_mode' => 'gratuite'])]]);
        $this->assertStringContainsString('adresse de livraison', $r->json('sales.rejected.0.reason'));

        // Poste Flutter : aucune clé de livraison, le comportement d'avant.
        $r = $this->pousser(['sales' => [$this->vente()]]);
        $this->assertSame([self::SALE], $r->json('sales.accepted'));
        $this->assertSame('0.00', Sale::findOrFail(self::SALE)->delivery_fee);
        $this->assertNull(Sale::findOrFail(self::SALE)->delivery_mode);
    }

    public function test_un_client_cree_hors_ligne_puis_sa_vente_sur_avance_dans_le_meme_envoi(): void
    {
        $r = $this->pousser([
            'customers' => [['id' => self::CLIENT, 'name' => 'Awa Kpossou', 'phone' => '0197112233', 'ifu' => '3201234567890', 'is_active' => true]],
            'sales' => [$this->vente(['payment_mode' => 'avance', 'customer_id' => self::CLIENT])],
        ]);

        $this->assertSame([self::CLIENT], $r->json('customers.accepted'));
        $this->assertSame([self::SALE], $r->json('sales.accepted'));
        $this->assertSame('3201234567890', Customer::findOrFail(self::CLIENT)->ifu);
        $this->assertSame('avance', Sale::findOrFail(self::SALE)->payment_mode);

        // Renvoi (accusé perdu) : succès silencieux, rien en double.
        $r = $this->pousser(['customers' => [['id' => self::CLIENT, 'name' => 'Awa Kpossou', 'phone' => '0197112233', 'is_active' => true]]]);
        $this->assertSame([self::CLIENT], $r->json('customers.accepted'));
        $this->assertSame(1, Customer::where('id', self::CLIENT)->count());
    }

    public function test_un_client_hors_ligne_deja_connu_est_fusionne_et_le_serveur_dit_lequel(): void
    {
        $existant = Customer::create(['name' => 'Awa Kpossou', 'phone' => '+229 0197112233', 'is_active' => true]);

        $r = $this->pousser(['customers' => [['id' => self::CLIENT, 'name' => 'AWA kpossou', 'phone' => '0197112233', 'is_active' => true]]]);

        $this->assertSame([self::CLIENT], $r->json('customers.accepted'));
        $this->assertSame($existant->id, $r->json('customers.merged.0.id_serveur'));
        $this->assertSame(self::CLIENT, $r->json('customers.merged.0.id'));
        $this->assertSame(1, Customer::count());
    }
}
