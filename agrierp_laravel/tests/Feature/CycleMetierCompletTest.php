<?php

namespace Tests\Feature;

use App\Livewire\Ventes\PosInterface;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\Customer;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Receivable;
use App\Models\Role;
use App\Models\Sale;
use App\Models\User;
use App\Services\FinancialReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.23 (Sprint 14) — CYCLE MÉTIER COMPLET, de la vente aux états
 * financiers.
 *
 * Chaque couche du projet était vérifiée isolément ; la CHAÎNE ne l'était
 * jamais. C'est précisément là que se logent les incohérences entre modules —
 * et c'est ce qui a permis au plus gros gap du projet de passer inaperçu :
 * aucune vente ne générait d'écriture comptable, donc toute la comptabilité
 * affichait zéro produit quel que soit le chiffre d'affaires réel.
 *
 * Ce test suit une vente unique à travers TOUS les modules qu'elle traverse :
 *     POS → stock → écriture comptable → grand livre → balance → bilan →
 *     compte de résultat → créance client.
 */
class CycleMetierCompletTest extends TestCase
{
    use RefreshDatabase;

    private Product $produit;

    private Customer $client;

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
            'email' => 'cycle@olouwachegoun.bj',
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

        // Plan comptable réel du projet, extrait nécessaire au cycle.
        foreach ([
            ['531', 'Caisse', 5],
            ['521201', 'Mobile Money', 5],
            ['411', 'Clients', 4],
            ['443', 'TVA facturée', 4],
            ['701', 'Ventes de produits', 7],
        ] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }

        $categorie = ProductCategory::create(['label' => 'Transformation', 'is_active' => true]);

        $this->produit = Product::create([
            'sku' => 'CYCLE-1',
            'name' => 'Poulet transformé',
            'category_id' => $categorie->id,
            'unit' => 'pièce',
            'pricing_mode' => 'fourchette',
            'price_min' => 3000,
            'price_max' => 5000,
            'tva_rate' => 18,
            'stock_qty' => 20,
            'is_active' => true,
        ]);

        $this->client = Customer::create(['name' => 'GBAGUIDI Solange', 'phone' => '+22997000000', 'is_active' => true]);
    }

    private function vendre(string $mode, float $montant, bool $avecClient = false): void
    {
        $composant = Livewire::test(PosInterface::class)
            ->set('cart', [[
                'product_id' => $this->produit->id,
                'name' => $this->produit->name,
                'unit' => $this->produit->unit,
                'lot_id' => null,
                'lot_code' => null,
                'qty' => 2,
                'montant' => $montant,
            ]])
            ->set('paymentMode', $mode);

        if ($avecClient) {
            $composant->set('customerId', $this->client->id);
        }

        if ($mode === 'especes') {
            $composant->set('cashReceived', $montant);
        }

        $composant->call('validateSale')->assertHasNoErrors();
    }

    /**
     * LE TEST CENTRAL : une vente au comptant traverse toute la chaîne et
     * arrive intacte dans les états financiers.
     */
    public function test_a_cash_sale_flows_all_the_way_to_the_financial_statements(): void
    {
        $this->vendre('especes', 59_000);

        // 1. La vente est enregistrée
        $vente = Sale::firstOrFail();
        $this->assertEquals(59_000, (float) $vente->total);

        // 2. Le stock est décrémenté
        $this->assertEquals(18, (float) $this->produit->fresh()->stock_qty);

        // 3. L'écriture comptable est générée ET rattachée à la vente
        $this->assertNotNull($vente->accounting_entry_id, "La vente doit generer son ecriture comptable.");
        $ecriture = AccountingEntry::with('lines.account')->findOrFail($vente->accounting_entry_id);
        $this->assertEquals('sale', $ecriture->source_type);

        // 4. L'écriture est équilibrée et ventilée HT / TVA
        $this->assertEquals($ecriture->total_debit, $ecriture->total_credit, "Ecriture desequilibree.");
        $parCompte = $ecriture->lines->keyBy(fn ($l) => $l->account->code);

        // 59 000 TTC à 18% : HT = 50 000, TVA = 9 000
        $this->assertEquals(59_000, (float) $parCompte['531']->debit, 'Caisse debitee du TTC.');
        $this->assertEquals(50_000, (float) $parCompte['701']->credit, 'Ventes creditees du HT.');
        $this->assertEquals(9_000, (float) $parCompte['443']->credit, 'TVA collectee.');

        // 5. Le grand livre du compte Caisse voit le mouvement
        $reports = app(FinancialReportService::class);
        $caisse = ChartOfAccount::where('code', '531')->firstOrFail();
        $gl = $reports->grandLivre($caisse->id, now()->startOfMonth()->format('Y-m-d'), now()->endOfMonth()->format('Y-m-d'));
        $this->assertEquals(59_000, $gl['total_debit']);

        // 6. La balance générale reste équilibrée
        $balance = $reports->balanceGenerale(now()->startOfMonth()->format('Y-m-d'), now()->endOfMonth()->format('Y-m-d'));
        $this->assertTrue($balance['is_balanced'], 'Balance desequilibree apres une vente.');

        // 7. Le compte de résultat voit le produit — c'est ce qui manquait
        $resultat = $reports->compteResultat(now()->format('Y-m-d'));
        $this->assertEquals(50_000, $resultat['ventes'], 'Le chiffre d affaires doit apparaitre au Compte de Resultat.');
        $this->assertEquals(50_000, $resultat['resultat_net']);

        // 8. Et le bilan est équilibré, avec le même résultat
        $bilan = $reports->bilan(now()->format('Y-m-d'));
        $this->assertTrue($bilan['is_balanced'], 'Bilan desequilibre.');
        $this->assertEquals($resultat['resultat_net'], $bilan['resultat']);
        $this->assertEquals(59_000, $bilan['total_tresorerie']);
    }

    /** Une vente à crédit crée une créance ET débite le compte Clients. */
    public function test_a_credit_sale_creates_a_receivable_and_debits_the_customer_account(): void
    {
        $this->vendre('credit', 59_000, avecClient: true);

        $this->assertEquals(1, Receivable::count(), 'Une vente a credit doit creer une creance.');

        $vente = Sale::firstOrFail();
        $ecriture = AccountingEntry::with('lines.account')->findOrFail($vente->accounting_entry_id);
        $parCompte = $ecriture->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertEquals(59_000, (float) $parCompte['411']->debit, 'Le compte Clients doit etre debite, pas la caisse.');
        $this->assertArrayNotHasKey('531', $parCompte->all(), 'Aucun encaissement en caisse sur une vente a credit.');

        // La créance et le grand livre disent la même chose.
        $bilan = app(FinancialReportService::class)->bilan(now()->format('Y-m-d'));
        $this->assertEquals(0.0, $bilan['total_tresorerie'], 'Rien n a ete encaisse.');
        $this->assertTrue($bilan['is_balanced']);
    }

    /** Le mode Mobile Money débite le bon compte de trésorerie. */
    public function test_mobile_money_debits_its_own_treasury_account(): void
    {
        $this->vendre('mobile_money', 59_000);

        $vente = Sale::firstOrFail();
        $ecriture = AccountingEntry::with('lines.account')->findOrFail($vente->accounting_entry_id);
        $parCompte = $ecriture->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertEquals(59_000, (float) $parCompte['521201']->debit);
        $this->assertArrayNotHasKey('531', $parCompte->all());
    }

    /** Un produit exonéré ne génère aucune ligne de TVA. */
    public function test_an_exempt_product_produces_no_vat_line(): void
    {
        $this->produit->update(['tva_rate' => 0]);

        $this->vendre('especes', 50_000);

        $vente = Sale::firstOrFail();
        $ecriture = AccountingEntry::with('lines.account')->findOrFail($vente->accounting_entry_id);
        $parCompte = $ecriture->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertArrayNotHasKey('443', $parCompte->all(), 'Aucune TVA sur un produit exonere.');
        $this->assertEquals(50_000, (float) $parCompte['701']->credit);
        $this->assertEquals($ecriture->total_debit, $ecriture->total_credit);
    }

    /** Plusieurs ventes s'accumulent correctement dans les états. */
    public function test_several_sales_accumulate_consistently(): void
    {
        $this->vendre('especes', 59_000);
        $this->vendre('mobile_money', 23_600);   // HT 20 000 + TVA 3 600

        $reports = app(FinancialReportService::class);

        $this->assertEquals(2, AccountingEntry::where('source_type', 'sale')->count());
        $this->assertEquals(70_000, $reports->compteResultat(now()->format('Y-m-d'))['ventes']);
        $this->assertEquals(82_600, $reports->bilan(now()->format('Y-m-d'))['total_tresorerie']);
        $this->assertTrue($reports->balanceGenerale(now()->startOfMonth()->format('Y-m-d'), now()->endOfMonth()->format('Y-m-d'))['is_balanced']);
    }

    /**
     * Une même vente ne doit jamais être comptabilisée deux fois — garde-fou
     * contre un double appel de l'Action.
     */
    public function test_a_sale_is_never_posted_twice(): void
    {
        $this->vendre('especes', 59_000);

        $vente = Sale::firstOrFail();
        app(\App\Actions\RecordSaleAccountingEntryAction::class)->execute($vente->fresh());

        $this->assertEquals(1, AccountingEntry::where('source_type', 'sale')->count());
    }
}
