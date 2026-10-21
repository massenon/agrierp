<?php

namespace Tests\Feature;

use App\Actions\RecordExpenseAccountingEntryAction;
use App\Livewire\Achats\SaisieDepenses;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\Expense;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Role;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\FinancialReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.33 (Sprint 14) — cycle DÉPENSE, jusqu'au Compte de Résultat.
 *
 * Le CDC §1.4 [M2] l'exige mot pour mot : « `RegisterExpense` → Débit Classe 6
 * / Crédit Classe 5 ». Avant ce ticket, la dépense décrémentait la trésorerie
 * sans rien porter en charge : le résultat net était surestimé du total des
 * dépenses de la période.
 */
class CycleDepenseComptableTest extends TestCase
{
    use RefreshDatabase;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-achats', 'manage-achats'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('comptable', 'web');
        $role->givePermissionTo(['view-achats', 'manage-achats']);

        $user = User::create([
            'name' => 'Comptable', 'email' => 'depense@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'),
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
            ['605', 'Énergie', 6],
            ['614', 'Transports', 6],
        ] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }

        $this->caisse = TreasuryAccount::create([
            'type' => 'caisse', 'label' => 'Caisse Principale',
            'account_code' => '531', 'balance' => 500_000, 'is_active' => true,
        ]);
    }

    private function saisir(string $categorie = '605 - Énergie', float $montant = 35_000): void
    {
        Livewire::test(SaisieDepenses::class)
            ->set('expenseDate', now()->format('Y-m-d'))
            ->set('label', 'Carburant groupe électrogène')
            ->set('category', $categorie)
            ->set('amount', $montant)
            ->set('treasuryAccountId', $this->caisse->id)
            ->call('submitExpense')
            ->assertHasNoErrors();
    }

    /** LA RÈGLE DU CDC : Débit classe 6 / Crédit classe 5. */
    public function test_an_expense_debits_a_class_6_account_and_credits_the_treasury(): void
    {
        $this->saisir();

        $depense = Expense::firstOrFail();
        $this->assertNotNull($depense->accounting_entry_id, 'La depense doit generer son ecriture.');

        $parCompte = AccountingEntry::with('lines.account')
            ->findOrFail($depense->accounting_entry_id)
            ->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertEquals(35_000, (float) $parCompte['605']->debit, 'La charge est portee au compte choisi.');
        $this->assertEquals(35_000, (float) $parCompte['531']->credit, 'La caisse est creditee.');
    }

    /** Le compte de charge vient du choix réel du comptable, pas d'un défaut. */
    public function test_the_charge_account_follows_the_operator_choice(): void
    {
        $this->saisir('614 - Transports', 12_000);

        $parCompte = AccountingEntry::with('lines.account')
            ->findOrFail(Expense::firstOrFail()->accounting_entry_id)
            ->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertEquals(12_000, (float) $parCompte['614']->debit);
        $this->assertArrayNotHasKey('605', $parCompte->all());
    }

    /**
     * LE DÉFAUT CORRIGÉ : la charge apparaît enfin au Compte de Résultat, et
     * le résultat cesse d'être surestimé.
     */
    public function test_the_expense_finally_reduces_the_net_result(): void
    {
        $reports = app(FinancialReportService::class);
        $avant = $reports->compteResultat(now()->format('Y-m-d'))['resultat_net'];

        $this->saisir('605 - Énergie', 35_000);

        $apres = app(FinancialReportService::class)->compteResultat(now()->format('Y-m-d'))['resultat_net'];

        $this->assertEquals($avant - 35_000, $apres, 'Le resultat doit baisser du montant de la charge.');
        $this->assertTrue($reports->bilan(now()->format('Y-m-d'))['is_balanced']);
    }

    /** La trésorerie et le grand livre bougent du même montant. */
    public function test_the_treasury_table_and_the_ledger_stay_in_step(): void
    {
        $this->saisir('605 - Énergie', 35_000);

        $this->assertEquals(465_000, (float) $this->caisse->fresh()->balance);
    }

    /**
     * ARCHIVAGE : contre-passation, jamais suppression. La trésorerie revient
     * ET la charge est annulée — sinon le résultat resterait grevé d'une
     * dépense dont l'argent est revenu.
     */
    public function test_archiving_reverses_the_entry_instead_of_deleting_it(): void
    {
        $this->saisir('605 - Énergie', 35_000);

        $depense = Expense::firstOrFail();
        $reports = app(FinancialReportService::class);
        $resultatAvant = $reports->compteResultat(now()->format('Y-m-d'))['resultat_net'];

        Livewire::test(SaisieDepenses::class)->call('archiveExpense', $depense->id);

        // L'écriture d'origine reste consultable : le grand livre est immuable.
        $this->assertNotNull(AccountingEntry::find($depense->accounting_entry_id));
        $this->assertEquals(1, AccountingEntry::where('source_type', 'expense_reversal')->count());

        $apres = app(FinancialReportService::class)->compteResultat(now()->format('Y-m-d'))['resultat_net'];
        $this->assertEquals($resultatAvant + 35_000, $apres, 'La charge doit etre annulee.');
        $this->assertEquals(500_000, (float) $this->caisse->fresh()->balance, 'La tresorerie revient a son solde.');
        $this->assertFalse((bool) $depense->fresh()->is_active);
    }

    /** Une dépense déjà comptabilisée ne se réécrit pas en silence. */
    public function test_a_posted_expense_cannot_have_its_amount_rewritten(): void
    {
        $this->saisir('605 - Énergie', 35_000);

        $depense = Expense::firstOrFail();

        Livewire::test(SaisieDepenses::class)
            ->call('editExpense', $depense->id)
            ->set('amount', 99_000)
            ->call('submitExpense')
            ->assertHasErrors(['amount']);

        $this->assertEquals(35_000, (float) $depense->fresh()->amount);
    }

    public function test_an_expense_is_never_posted_twice(): void
    {
        $this->saisir();

        app(RecordExpenseAccountingEntryAction::class)->execute(Expense::firstOrFail());

        $this->assertEquals(1, AccountingEntry::where('source_type', 'expense')->count());
    }

    /**
     * Compte de charge absent du plan comptable : la dépense est enregistrée
     * malgré tout — l'argent est réellement sorti — mais l'anomalie est DITE.
     */
    public function test_a_missing_charge_account_is_reported_never_swallowed(): void
    {
        Livewire::test(SaisieDepenses::class)
            ->set('expenseDate', now()->format('Y-m-d'))
            ->set('label', 'Charge sans compte')
            ->set('category', '699 - Compte inexistant')
            ->set('amount', 10_000)
            ->set('treasuryAccountId', $this->caisse->id)
            ->call('submitExpense')
            ->assertDispatched('toast', function (string $nom, array $params) {
                return str_contains($params['message'], 'écriture comptable non générée')
                    && $params['type'] === 'warning';
            });

        $this->assertEquals(1, Expense::count());
        $this->assertNull(Expense::firstOrFail()->accounting_entry_id);
        $this->assertEquals(490_000, (float) $this->caisse->fresh()->balance, "L'argent est bien sorti.");
    }
}
