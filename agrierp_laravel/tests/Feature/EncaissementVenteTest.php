<?php

namespace Tests\Feature;

use App\Actions\CreditTreasuryForSaleAction;
use App\Livewire\Ventes\PosInterface;
use App\Models\ChartOfAccount;
use App\Models\Customer;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\Sale;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.32 (Sprint 14) — ENCAISSEMENT RÉEL D'UNE VENTE.
 *
 * 🔴 Défaut trouvé en simulant cinq mois d'exploitation (ticket 14.31) : une
 * vente au comptant n'augmentait jamais la caisse. `PosInterface` ne contenait
 * aucune référence à `TreasuryAccount`.
 *
 * Le point qui compte : la trésorerie est tenue en DEUX livres — la table
 * `treasury_accounts` (KPI du tableau de bord) et les comptes de classe 5 du
 * grand livre (Bilan, rapprochement bancaire). L'écriture de vente créditait
 * bien le second ; le premier ne bougeait pas. Ils divergeaient dès la
 * première vente, et dans un seul sens : seuls les décaissements faisaient
 * bouger le solde affiché, qui dérivait donc vers le négatif quel que soit le
 * chiffre d'affaires.
 */
class EncaissementVenteTest extends TestCase
{
    use RefreshDatabase;

    private Product $produit;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-ventes', 'manage-ventes'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('caissier', 'web');
        $role->givePermissionTo(['view-ventes', 'manage-ventes']);

        $user = User::create([
            'name' => 'Caissière', 'email' => 'encaissement@olouwachegoun.bj', 'password' => bcrypt('AgriERP@2026'),
        ]);
        $user->assignRole($role);
        $this->actingAs($user);

        FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);

        foreach ([
            ['531', 'Caisse', 5],
            ['521101', 'Banque', 5],
            ['521201', 'Mobile Money', 5],
            ['411', 'Clients', 4],
            ['701', 'Ventes de produits', 7],
        ] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }

        foreach ([
            ['caisse', 'Caisse Principale', '531', 100_000],
            ['banque', 'Compte Bancaire', '521101', 500_000],
            ['mobile_money', 'Mobile Money', '521201', 0],
        ] as [$type, $label, $code, $solde]) {
            TreasuryAccount::create([
                'type' => $type, 'label' => $label, 'account_code' => $code,
                'balance' => $solde, 'is_active' => true,
            ]);
        }

        $categorie = ProductCategory::create(['label' => 'Aviculture', 'is_active' => true]);

        $this->produit = Product::create([
            'sku' => 'AVI-001', 'name' => 'Poulet goliath', 'category_id' => $categorie->id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 4_000, 'price_max' => 8_000,
            'tva_rate' => 0, 'stock_qty' => 50, 'is_active' => true,
        ]);
    }

    private function vendre(string $mode, float $montant = 12_000): Sale
    {
        Livewire::test(PosInterface::class)
            ->set('paymentMode', $mode)
            ->set('cart', [[
                'product_id' => $this->produit->id,
                'name' => $this->produit->name,
                'unit' => $this->produit->unit,
                'qty' => 2,
                'montant' => $montant,
                'lot_id' => null,
                'lot_code' => null,
            ]])
            ->call('validateSale');

        return Sale::latest()->firstOrFail();
    }

    private function solde(string $code): float
    {
        return (float) TreasuryAccount::where('account_code', $code)->value('balance');
    }

    /** LE DÉFAUT CORRIGÉ : une vente en espèces alimente la caisse. */
    public function test_a_cash_sale_credits_the_till(): void
    {
        $this->vendre('especes');

        $this->assertEquals(112_000, $this->solde('531'), 'La caisse doit augmenter du montant encaisse.');
    }

    /** Chaque mode alimente SON compte, jamais un autre. */
    public function test_each_payment_mode_credits_its_own_account(): void
    {
        $this->vendre('mobile_money');

        $this->assertEquals(12_000, $this->solde('521201'));
        $this->assertEquals(100_000, $this->solde('531'), 'La caisse ne bouge pas.');
        $this->assertEquals(500_000, $this->solde('521101'), 'La banque non plus.');
    }

    public function test_a_bank_transfer_sale_credits_the_bank(): void
    {
        $this->vendre('virement');

        $this->assertEquals(512_000, $this->solde('521101'));
    }

    /**
     * ⚠️ VENTE À CRÉDIT : rien n'est encaissé. Créditer ici anticiperait un
     * règlement qui n'a pas eu lieu — c'est `ProfileClient`/`SuiviDettes` qui
     * créditent la trésorerie au moment du paiement.
     */
    public function test_a_credit_sale_moves_no_treasury_account(): void
    {
        $client = Customer::create(['name' => 'Revendeur', 'phone' => '+22997000001', 'credit_limit' => 500_000, 'is_active' => true]);

        Livewire::test(PosInterface::class)
            ->set('paymentMode', 'credit')
            ->set('customerId', $client->id)
            ->set('cart', [[
                'product_id' => $this->produit->id, 'name' => $this->produit->name, 'unit' => 'u',
                'qty' => 2, 'montant' => 12_000, 'lot_id' => null, 'lot_code' => null,
            ]])
            ->call('validateSale');

        $this->assertEquals(100_000, $this->solde('531'));
        $this->assertEquals(500_000, $this->solde('521101'));
        $this->assertEquals(0, $this->solde('521201'));
    }

    /**
     * LA PROPRIÉTÉ QUI COMPTE : les deux livres de trésorerie concordent.
     * Le compte de classe 5 du grand livre et la table `treasury_accounts`
     * doivent bouger du même montant, sur le même compte.
     */
    public function test_the_ledger_and_the_treasury_table_stay_in_step(): void
    {
        $vente = $this->vendre('especes', 15_000);

        $ligne = $vente->fresh('lines')->accounting_entry_id
            ? \App\Models\AccountingEntryLine::whereHas('entry', fn ($q) => $q->where('id', $vente->accounting_entry_id))
                ->whereHas('account', fn ($q) => $q->where('code', '531'))
                ->first()
            : null;

        $this->assertNotNull($ligne, 'La vente doit debiter 531 au grand livre.');
        $this->assertEquals(15_000, (float) $ligne->debit);
        $this->assertEquals(115_000, $this->solde('531'), 'La table doit bouger du meme montant.');
    }

    /** Un compte de trésorerie absent ne fait pas échouer la vente. */
    public function test_a_missing_treasury_account_does_not_break_the_sale(): void
    {
        TreasuryAccount::where('account_code', '521201')->delete();

        $vente = Sale::create([
            'payment_mode' => 'mobile_money', 'subtotal' => 5_000, 'discount' => 0, 'total' => 5_000,
            'delivery_fee' => 0, 'status' => 'validee',
        ]);

        $this->assertNull(app(CreditTreasuryForSaleAction::class)->execute($vente));
    }
}
