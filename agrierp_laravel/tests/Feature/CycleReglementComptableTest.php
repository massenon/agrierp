<?php

namespace Tests\Feature;

use App\Actions\RecordSettlementAccountingEntryAction;
use App\Livewire\Achats\DettesFournisseurs;
use App\Livewire\Ventes\SuiviDettes;
use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\ChartOfAccount;
use App\Models\Customer;
use App\Models\FiscalYear;
use App\Models\Payable;
use App\Models\Permission;
use App\Models\Receivable;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\FinancialReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.34 (Sprint 14) — cycle RÈGLEMENT, client et fournisseur.
 *
 * Le point qui compte : encaisser une créance déplaçait l'argent dans la table
 * `treasury_accounts` sans jamais l'inscrire au grand livre. **411 Clients
 * restait débité après paiement** — le Bilan portait indéfiniment des créances
 * encaissées, et sous-évaluait la trésorerie d'autant.
 */
class CycleReglementComptableTest extends TestCase
{
    use RefreshDatabase;

    private TreasuryAccount $caisse;

    private Customer $client;

    private Supplier $fournisseur;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-ventes', 'manage-ventes', 'view-achats', 'manage-achats'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('admin', 'web');
        $role->givePermissionTo(['view-ventes', 'manage-ventes', 'view-achats', 'manage-achats']);

        $user = User::create([
            'name' => 'Gérant', 'email' => 'reglement@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'),
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
            ['411', 'Clients', 4],
            ['401', 'Fournisseurs', 4],
        ] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }

        $this->caisse = TreasuryAccount::create([
            'type' => 'caisse', 'label' => 'Caisse Principale',
            'account_code' => '531', 'balance' => 200_000, 'is_active' => true,
        ]);

        $this->client = Customer::create(['name' => 'Restaurant LA TERRASSE', 'phone' => '+22997202020', 'credit_limit' => 400_000, 'is_active' => true]);
        $this->fournisseur = Supplier::create(['name' => 'Provenderie du Plateau', 'phone' => '+22997112233', 'is_active' => true]);
    }

    private function soldeCompte(string $code): float
    {
        $compte = ChartOfAccount::where('code', $code)->firstOrFail();

        return round(
            (float) AccountingEntryLine::where('account_id', $compte->id)->sum('debit')
            - (float) AccountingEntryLine::where('account_id', $compte->id)->sum('credit'),
            2
        );
    }

    /**
     * Ouvre une dette au grand livre, comme le ferait un achat à crédit
     * (`RecordPurchaseAccountingEntryAction`) : Crédit 401 / Débit 601.
     *
     * ⚠️ Sans cette ouverture, 401 afficherait un solde DÉBITEUR après
     * règlement — arithmétiquement exact, mais on ne testerait alors que le
     * sens de l'écriture, pas la propriété qui compte : que la dette **se
     * solde**.
     */
    private function ouvrirDetteAuGrandLivre(float $montant): void
    {
        $charges = ChartOfAccount::firstOrCreate(
            ['code' => '601'],
            ['label' => 'Achats de marchandises', 'class' => 6, 'is_active' => true]
        );

        app(\App\Services\AccountingEntryService::class)->record(
            lines: [
                ['account_id' => $charges->id, 'debit' => $montant, 'credit' => 0],
                ['account_id' => ChartOfAccount::where('code', '401')->value('id'), 'debit' => 0, 'credit' => $montant],
            ],
            entryDate: now()->format('Y-m-d'),
        );
    }

    // -------------------------------------------------------------- clients

    /** LE DÉFAUT CORRIGÉ : 411 se solde enfin quand le client paie. */
    public function test_collecting_a_receivable_clears_the_customer_account(): void
    {
        $creance = Receivable::create([
            'customer_id' => $this->client->id, 'amount' => 120_000, 'amount_paid' => 0,
            'due_date' => now()->addDays(30)->format('Y-m-d'), 'status' => 'en_cours',
        ]);

        // Créance ouverte au grand livre, comme le ferait la vente à crédit.
        app(\App\Services\AccountingEntryService::class)->record(
            lines: [
                ['account_id' => ChartOfAccount::where('code', '411')->value('id'), 'debit' => 120_000, 'credit' => 0],
                ['account_id' => ChartOfAccount::where('code', '531')->value('id'), 'debit' => 0, 'credit' => 120_000],
            ],
            entryDate: now()->format('Y-m-d'),
        );

        $this->assertEquals(120_000, $this->soldeCompte('411'));

        Livewire::test(SuiviDettes::class)
            ->call('openPaymentModal', $creance->id)
            ->set('paymentMontant', 120_000)
            ->set('paymentTreasuryId', $this->caisse->id)
            ->call('confirmPayment')
            ->assertHasNoErrors();

        $this->assertEquals(0, $this->soldeCompte('411'), 'La creance doit etre soldee au grand livre.');
        $this->assertEquals(1, AccountingEntry::where('source_type', 'receivable_settlement')->count());
    }

    /** La table de trésorerie et le grand livre bougent du même montant. */
    public function test_the_treasury_table_and_the_ledger_move_together(): void
    {
        $creance = Receivable::create([
            'customer_id' => $this->client->id, 'amount' => 80_000, 'amount_paid' => 0,
            'due_date' => now()->addDays(15)->format('Y-m-d'), 'status' => 'en_cours',
        ]);

        Livewire::test(SuiviDettes::class)
            ->call('openPaymentModal', $creance->id)
            ->set('paymentMontant', 50_000)
            ->set('paymentTreasuryId', $this->caisse->id)
            ->call('confirmPayment');

        $this->assertEquals(250_000, (float) $this->caisse->fresh()->balance, 'Table de tresorerie.');
        $this->assertEquals(50_000, $this->soldeCompte('531'), 'Grand livre : meme montant.');
        $this->assertEquals(-50_000, $this->soldeCompte('411'), 'Creance apuree a due concurrence.');
    }

    /** Un règlement partiel n'écrit que ce qui est réellement encaissé. */
    public function test_a_partial_collection_posts_only_what_is_received(): void
    {
        $creance = Receivable::create([
            'customer_id' => $this->client->id, 'amount' => 100_000, 'amount_paid' => 0,
            'due_date' => now()->addDays(20)->format('Y-m-d'), 'status' => 'en_cours',
        ]);

        Livewire::test(SuiviDettes::class)
            ->call('openPaymentModal', $creance->id)
            ->set('paymentMontant', 30_000)
            ->set('paymentTreasuryId', $this->caisse->id)
            ->call('confirmPayment');

        $this->assertEquals(30_000, (float) $creance->fresh()->amount_paid);
        $this->assertEquals(30_000, $this->soldeCompte('531'));
    }

    // ---------------------------------------------------------- fournisseurs

    /** 401 se solde enfin quand la ferme paie son fournisseur. */
    public function test_paying_a_supplier_clears_the_payable_account(): void
    {
        Payable::create([
            'supplier_id' => $this->fournisseur->id, 'amount' => 90_000, 'amount_paid' => 0,
            'due_date' => now()->addDays(30)->format('Y-m-d'), 'status' => 'en_cours',
        ]);

        $this->ouvrirDetteAuGrandLivre(90_000);
        $this->assertEquals(-90_000, $this->soldeCompte('401'), 'Dette ouverte : solde crediteur.');

        Livewire::test(DettesFournisseurs::class)
            ->call('openPaymentModal')
            ->set('paymentSupplierId', $this->fournisseur->id)
            ->set('paymentDate', now()->format('Y-m-d'))
            ->set('paymentAmount', 90_000)
            ->set('paymentTreasuryAccountId', $this->caisse->id)
            ->call('submitPaiementFournisseur')
            ->assertHasNoErrors();

        $this->assertEquals(0, $this->soldeCompte('401'), 'La dette doit etre soldee au grand livre.');
        $this->assertEquals(-90_000, $this->soldeCompte('531'), 'La tresorerie est creditee.');
        $this->assertEquals(110_000, (float) $this->caisse->fresh()->balance);
    }

    /**
     * ⚠️ LE CAS QUI DEMANDE DE LA PRÉCISION : un versement supérieur au total
     * dû ne solde que ce qui existe. C'est le montant RÉELLEMENT imputé qui
     * doit être comptabilisé, pas celui saisi.
     */
    public function test_an_overpayment_posts_only_the_amount_actually_applied(): void
    {
        Payable::create([
            'supplier_id' => $this->fournisseur->id, 'amount' => 40_000, 'amount_paid' => 0,
            'due_date' => now()->addDays(10)->format('Y-m-d'), 'status' => 'en_cours',
        ]);

        $this->ouvrirDetteAuGrandLivre(40_000);

        Livewire::test(DettesFournisseurs::class)
            ->call('openPaymentModal')
            ->set('paymentSupplierId', $this->fournisseur->id)
            ->set('paymentDate', now()->format('Y-m-d'))
            ->set('paymentAmount', 60_000)      // 20 000 de trop
            ->set('paymentTreasuryAccountId', $this->caisse->id)
            ->call('submitPaiementFournisseur');

        $this->assertEquals(0, $this->soldeCompte('401'), 'Seule la dette reelle est apuree, pas les 60 000 saisis.');
        $this->assertEquals(-40_000, $this->soldeCompte('531'), 'Et seul ce montant sort du grand livre.');
    }

    /** Plusieurs dettes soldées en FIFO : UNE seule écriture, pas une par dette. */
    public function test_a_single_entry_covers_a_fifo_settlement(): void
    {
        foreach ([30_000, 25_000, 20_000] as $i => $montant) {
            Payable::create([
                'supplier_id' => $this->fournisseur->id, 'amount' => $montant, 'amount_paid' => 0,
                'due_date' => now()->addDays(($i + 1) * 10)->format('Y-m-d'), 'status' => 'en_cours',
            ]);
        }

        $this->ouvrirDetteAuGrandLivre(75_000);

        Livewire::test(DettesFournisseurs::class)
            ->call('openPaymentModal')
            ->set('paymentSupplierId', $this->fournisseur->id)
            ->set('paymentDate', now()->format('Y-m-d'))
            ->set('paymentAmount', 75_000)
            ->set('paymentTreasuryAccountId', $this->caisse->id)
            ->call('submitPaiementFournisseur');

        $this->assertEquals(1, AccountingEntry::where('source_type', 'payable_settlement')->count(),
            'Un versement est un fait comptable unique, meme s il apure 3 dettes.');
        $this->assertEquals(0, $this->soldeCompte('401'), 'Les 3 dettes sont soldees par une ecriture unique.');
        $this->assertEquals(3, Payable::where('status', 'soldee')->count());
    }

    // ------------------------------------------------------------- garde-fous

    /** Aucune écriture à zéro n'encombre le journal. */
    public function test_a_zero_settlement_leaves_no_entry(): void
    {
        $action = app(RecordSettlementAccountingEntryAction::class);

        $this->assertNull($action->collectFromCustomer($this->caisse, 0));
        $this->assertNull($action->payToSupplier($this->caisse, 0));
        $this->assertEquals(0, AccountingEntry::count());
    }

    /** Plan comptable incomplet : signalé par un retour null, jamais deviné. */
    public function test_a_missing_third_party_account_produces_no_entry(): void
    {
        ChartOfAccount::where('code', '411')->delete();

        $this->assertNull(
            app(RecordSettlementAccountingEntryAction::class)->collectFromCustomer($this->caisse, 10_000)
        );
    }

    /** Le Bilan reste équilibré après des règlements dans les deux sens. */
    public function test_the_balance_sheet_stays_balanced_after_settlements(): void
    {
        $creance = Receivable::create([
            'customer_id' => $this->client->id, 'amount' => 60_000, 'amount_paid' => 0,
            'due_date' => now()->addDays(30)->format('Y-m-d'), 'status' => 'en_cours',
        ]);

        Payable::create([
            'supplier_id' => $this->fournisseur->id, 'amount' => 45_000, 'amount_paid' => 0,
            'due_date' => now()->addDays(30)->format('Y-m-d'), 'status' => 'en_cours',
        ]);

        $this->ouvrirDetteAuGrandLivre(45_000);

        Livewire::test(SuiviDettes::class)
            ->call('openPaymentModal', $creance->id)
            ->set('paymentMontant', 60_000)
            ->set('paymentTreasuryId', $this->caisse->id)
            ->call('confirmPayment');

        Livewire::test(DettesFournisseurs::class)
            ->call('openPaymentModal')
            ->set('paymentSupplierId', $this->fournisseur->id)
            ->set('paymentDate', now()->format('Y-m-d'))
            ->set('paymentAmount', 45_000)
            ->set('paymentTreasuryAccountId', $this->caisse->id)
            ->call('submitPaiementFournisseur');

        $this->assertTrue(app(FinancialReportService::class)->bilan(now()->format('Y-m-d'))['is_balanced']);
    }
}
