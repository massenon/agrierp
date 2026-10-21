<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\Sale;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\Mecef\MecefGatewayInterface;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket U14 — `sale.mecef_failed_on_sync` : l'échec de la facture d'une vente REÇUE D'UN POSTE est écrit au journal
 * d'audit, avec un libellé français.
 *
 * 🔴 Avant : S-T13 a sorti l'appel MeCeF de la transaction de l'envoi et, avec lui, la ligne d'audit qu'écrivait
 * l'ancien `catch` (`sale.mecef_failed_on_sync`) — l'échec ne laissait plus de trace qu'au journal des erreurs. Et la
 * clé n'avait jamais eu de libellé : les lignes déjà écrites s'affichaient sous leur nom technique (au web et au poste,
 * qui reçoit `ACTION_LABELS` par `outils/libelles_audit.py`).
 */
class EchecMecefEnvoiAuditTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private string $jeton;

    private Product $produit;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-ventes', 'manage-ventes'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('caissier', 'web')->givePermissionTo(['view-ventes', 'manage-ventes']);
        $caissier = User::create([
            'name' => 'Caissière', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com',
            'password' => bcrypt(self::MDP), 'is_active' => true,
        ]);
        $caissier->assignRole('caissier');

        FiscalYear::create([
            'year' => now()->year, 'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'), 'status' => 'ouvert',
        ]);
        foreach ([['411', 'Clients', 4], ['531', 'Caisse', 5], ['701', 'Ventes de marchandises', 7], ['443', 'TVA collectée', 4]] as [$code, $libelle, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $libelle, 'class' => $classe, 'is_active' => true]);
        }
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);

        $categorie = ProductCategory::create(['label' => 'Épicerie', 'is_active' => true]);
        $this->produit = Product::create([
            'sku' => 'EPI-001', 'name' => 'Piment', 'category_id' => $categorie->id, 'unit' => 'kg',
            'pricing_mode' => 'fourchette', 'price_min' => 400, 'price_max' => 600, 'tva_rate' => 0,
            'stock_qty' => 20, 'is_active' => true,
        ]);

        $this->jeton = $this->postJson('/api/auth/login', [
            'identifiant' => 'caisse', 'password' => self::MDP, 'device_name' => 'poste-caisse-01',
        ])->json('token');
    }

    private function dispositif(bool $accepte): void
    {
        $this->app->instance(MecefGatewayInterface::class, new class($accepte) implements MecefGatewayInterface
        {
            public function __construct(private bool $accepte) {}

            public function transmit(Sale $sale): array
            {
                return $this->accepte
                    ? ['success' => true, 'qr_ref' => 'NIM-TEST', 'message' => 'Facture normalisée.']
                    : ['success' => false, 'qr_ref' => null, 'message' => 'Dispositif MeCeF injoignable (essai).'];
            }
        });
    }

    private function pousserVente(): void
    {
        $this->withHeader('Authorization', 'Bearer '.$this->jeton)->postJson('/api/sync/push', [
            'device_id' => 'poste-caisse-01',
            'sales' => [[
                'id' => '22222222-2222-4222-8222-222222222222',
                'payment_mode' => 'especes', 'subtotal' => 1_000, 'discount' => 0, 'total' => 1_000,
                'status' => 'validee',
                'lines' => [['product_id' => $this->produit->id, 'qty' => 2, 'unit_price' => 500, 'manual_total_amount' => 1_000]],
            ]],
        ])->assertOk()->assertJsonPath('sales.accepted.0', '22222222-2222-4222-8222-222222222222');
    }

    public function test_un_echec_mecef_d_une_vente_recue_est_ecrit_au_journal_d_audit(): void
    {
        $this->dispositif(false);

        $this->pousserVente();

        $this->assertSame('erreur', Sale::findOrFail('22222222-2222-4222-8222-222222222222')->mecef_status);
        $this->assertSame(1, AuditLog::where('action', 'sale.mecef_failed_on_sync')->where('module', 'facturation')->count());
    }

    public function test_une_facture_transmise_n_ecrit_pas_d_echec(): void
    {
        $this->dispositif(true);

        $this->pousserVente();

        $this->assertSame('transmise', Sale::findOrFail('22222222-2222-4222-8222-222222222222')->mecef_status);
        $this->assertSame(0, AuditLog::where('action', 'sale.mecef_failed_on_sync')->count());
    }

    public function test_la_cle_a_son_libelle_francais(): void
    {
        $ligne = new AuditLog(['action' => 'sale.mecef_failed_on_sync']);

        $this->assertSame('Vente reçue d\'un poste : échec de la transmission MeCeF', $ligne->action_label);
    }
}
