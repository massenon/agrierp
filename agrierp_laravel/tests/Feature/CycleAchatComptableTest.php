<?php

namespace Tests\Feature;

use App\Livewire\Achats\EnregistrerAchat;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Payable;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\FinancialReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.24 (Sprint 14) — cycle ACHAT complet, jusqu'aux états financiers.
 *
 * Pendant du `CycleMetierCompletTest` côté fournisseurs. Le cas qui compte est
 * le **règlement partiel** : il produit une écriture à plusieurs lignes
 * (trésorerie + dette fournisseur), la forme que le CDC prévoit et qu'une
 * simple paire débit/crédit ne saurait représenter.
 */
class CycleAchatComptableTest extends TestCase
{
    use RefreshDatabase;

    private Supplier $fournisseur;

    private Product $produit;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-achats', 'manage-achats'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('admin', 'web');
        $role->givePermissionTo(['view-achats', 'manage-achats']);

        $user = User::create([
            'name' => 'Acheteur',
            'email' => 'achat@fermeolouwachegoun.com',
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

        foreach ([
            ['531', 'Caisse', 5],
            ['401', 'Fournisseurs', 4],
            ['445', 'TVA récupérable', 4],
            ['601', 'Achats de marchandises', 6],
        ] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }

        $this->caisse = TreasuryAccount::create([
            'type' => 'caisse', 'label' => 'Caisse Principale',
            'account_code' => '531', 'balance' => 500_000, 'is_active' => true,
        ]);

        $this->fournisseur = Supplier::create([
            'name' => 'Provenderie du Plateau', 'phone' => '+22997111111', 'is_active' => true,
        ]);

        $categorie = ProductCategory::create(['label' => 'Provende', 'is_active' => true]);

        $this->produit = Product::create([
            'sku' => 'ALI-PONTE', 'name' => 'Aliment ponte', 'category_id' => $categorie->id,
            'unit' => 'kg', 'pricing_mode' => 'fourchette', 'price_min' => 500, 'price_max' => 700,
            'tva_rate' => 18, 'stock_qty' => 0, 'is_active' => true,
        ]);
    }

    private function acheter(float $montantPaye): void
    {
        Livewire::test(EnregistrerAchat::class)
            ->set('supplierId', $this->fournisseur->id)
            ->set('treasuryAccountId', $this->caisse->id)
            ->set('paymentMode', 'especes')
            ->set('cart', [[
                'product_id' => $this->produit->id,
                'name' => $this->produit->name,
                'unit' => $this->produit->unit,
                'qty' => 100,
                'unit_price' => 590,     // 59 000 TTC à 18% -> HT 50 000, TVA 9 000
            ]])
            ->set('amountPaid', $montantPaye)
            ->call('submitAchat')
            ->assertHasNoErrors();
    }

    public function test_a_fully_paid_purchase_debits_charges_and_credits_treasury(): void
    {
        $this->acheter(59_000);

        $achat = Purchase::firstOrFail();
        $this->assertNotNull($achat->accounting_entry_id, "L'achat doit generer son ecriture comptable.");

        $ecriture = AccountingEntry::with('lines.account')->findOrFail($achat->accounting_entry_id);
        $parCompte = $ecriture->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertEquals(50_000, (float) $parCompte['601']->debit, 'Charges au HT.');
        $this->assertEquals(9_000, (float) $parCompte['445']->debit, 'TVA recuperable.');
        $this->assertEquals(59_000, (float) $parCompte['531']->credit, 'Caisse creditee du TTC.');
        $this->assertEquals($ecriture->total_debit, $ecriture->total_credit);

        // Aucune dette fournisseur si tout est réglé.
        $this->assertEquals(0, Payable::count());

        // Le stock est entré.
        $this->assertEquals(100, (float) $this->produit->fresh()->stock_qty);
    }

    /**
     * LE CAS QUI JUSTIFIE L'ÉCRITURE À PLUSIEURS LIGNES : règlement partiel.
     */
    public function test_a_partial_payment_splits_between_treasury_and_supplier_debt(): void
    {
        $this->acheter(20_000);   // sur 59 000

        $achat = Purchase::firstOrFail();
        $ecriture = AccountingEntry::with('lines.account')->findOrFail($achat->accounting_entry_id);
        $parCompte = $ecriture->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertCount(4, $ecriture->lines, '601 + 445 + tresorerie + 401 = 4 lignes.');
        $this->assertEquals(20_000, (float) $parCompte['531']->credit, 'Part reellement reglee.');
        $this->assertEquals(39_000, (float) $parCompte['401']->credit, 'Solde en dette fournisseur.');
        $this->assertEquals($ecriture->total_debit, $ecriture->total_credit);

        // La dette comptable et la dette métier disent la même chose.
        $dette = Payable::firstOrFail();
        $this->assertEquals(39_000, (float) $dette->amount - (float) $dette->amount_paid);
    }

    /** Achat entièrement à crédit : rien ne sort de la trésorerie. */
    public function test_a_fully_unpaid_purchase_credits_only_the_supplier_account(): void
    {
        $this->acheter(0);

        $ecriture = AccountingEntry::with('lines.account')->findOrFail(Purchase::firstOrFail()->accounting_entry_id);
        $parCompte = $ecriture->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertArrayNotHasKey('531', $parCompte->all(), "Aucun decaissement s'il n'y a pas de reglement.");
        $this->assertEquals(59_000, (float) $parCompte['401']->credit);
        $this->assertEquals($ecriture->total_debit, $ecriture->total_credit);
    }

    /**
     * L'effet attendu sur les états : les charges apparaissent enfin, et le
     * résultat net cesse d'être surestimé.
     */
    public function test_purchases_finally_appear_in_the_income_statement(): void
    {
        $this->acheter(59_000);

        $reports = app(FinancialReportService::class);
        $resultat = $reports->compteResultat(now()->format('Y-m-d'));

        $this->assertEquals(50_000, $resultat['achats'], 'Les achats doivent apparaitre au Compte de Resultat.');
        $this->assertEquals(-50_000, $resultat['resultat_net'], 'Sans vente, un achat produit une perte.');

        $balance = $reports->balanceGenerale(now()->startOfMonth()->format('Y-m-d'), now()->endOfMonth()->format('Y-m-d'));
        $this->assertTrue($balance['is_balanced']);

        $bilan = $reports->bilan(now()->format('Y-m-d'));
        $this->assertTrue($bilan['is_balanced']);
        $this->assertEquals($resultat['resultat_net'], $bilan['resultat']);
    }

    public function test_a_purchase_is_never_posted_twice(): void
    {
        $this->acheter(59_000);

        $achat = Purchase::firstOrFail();
        app(\App\Actions\RecordPurchaseAccountingEntryAction::class)
            ->execute($achat->fresh('lines'), $this->caisse->id, 59_000);

        $this->assertEquals(1, AccountingEntry::where('source_type', 'purchase')->count());
    }
}
