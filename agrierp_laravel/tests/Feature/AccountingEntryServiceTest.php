<?php

namespace Tests\Feature;

use App\Exceptions\NoOpenFiscalYearException;
use App\Exceptions\UnbalancedAccountingEntryException;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Services\AccountingEntryService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 10.2 (Sprint 10) — scénarios explicitement attendus par
 * Document 07_TESTING_QA.md : "la somme des débits égale toujours la
 * somme des crédits, échec explicite si compte débité = compte crédité
 * sur une écriture manuelle."
 */
class AccountingEntryServiceTest extends TestCase
{
    use RefreshDatabase;

    private function openFiscalYear(): FiscalYear
    {
        return FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);
    }

    private function account(string $code, string $label, int $class): ChartOfAccount
    {
        return ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $class, 'is_active' => true]);
    }

    public function test_balanced_entry_is_recorded_successfully(): void
    {
        $this->openFiscalYear();
        $treasury = $this->account('531', 'Caisse', 5);
        $sales = $this->account('701', 'Ventes', 7);

        $entry = app(AccountingEntryService::class)->record(
            lines: [
                ['account_id' => $treasury->id, 'debit' => 10000, 'credit' => 0],
                ['account_id' => $sales->id, 'debit' => 0, 'credit' => 10000],
            ],
            entryDate: now()->format('Y-m-d'),
            sourceType: 'sale',
        );

        $this->assertDatabaseHas('accounting_entries', ['id' => $entry->id]);
        $this->assertCount(2, $entry->lines);
        $this->assertEquals(10000.0, $entry->total_debit);
        $this->assertEquals(10000.0, $entry->total_credit);
    }

    public function test_unbalanced_entry_is_rejected_and_nothing_is_persisted(): void
    {
        $this->openFiscalYear();
        $treasury = $this->account('531', 'Caisse', 5);
        $sales = $this->account('701', 'Ventes', 7);

        $this->expectException(UnbalancedAccountingEntryException::class);

        try {
            app(AccountingEntryService::class)->record(
                lines: [
                    ['account_id' => $treasury->id, 'debit' => 10000, 'credit' => 0],
                    ['account_id' => $sales->id, 'debit' => 0, 'credit' => 9000],
                ],
                entryDate: now()->format('Y-m-d'),
            );
        } finally {
            $this->assertDatabaseCount('accounting_entries', 0);
            $this->assertDatabaseCount('accounting_entry_lines', 0);
        }
    }

    public function test_manual_entry_rejects_identical_debit_and_credit_account(): void
    {
        $this->openFiscalYear();
        $treasury = $this->account('531', 'Caisse', 5);

        $this->expectException(\InvalidArgumentException::class);

        app(AccountingEntryService::class)->recordManual(
            debitAccountId: $treasury->id,
            creditAccountId: $treasury->id,
            amount: 5000,
            entryDate: now()->format('Y-m-d'),
        );
    }

    public function test_manual_entry_with_distinct_accounts_succeeds(): void
    {
        $this->openFiscalYear();
        $treasury = $this->account('531', 'Caisse', 5);
        $expense = $this->account('604', 'Fournitures', 6);

        $entry = app(AccountingEntryService::class)->recordManual(
            debitAccountId: $expense->id,
            creditAccountId: $treasury->id,
            amount: 5000,
            entryDate: now()->format('Y-m-d'),
        );

        $this->assertEquals(5000.0, $entry->total_debit);
        $this->assertEquals(5000.0, $entry->total_credit);
    }

    public function test_recording_without_an_open_fiscal_year_is_rejected(): void
    {
        $treasury = $this->account('531', 'Caisse', 5);
        $sales = $this->account('701', 'Ventes', 7);

        $this->expectException(NoOpenFiscalYearException::class);

        app(AccountingEntryService::class)->record(
            lines: [
                ['account_id' => $treasury->id, 'debit' => 1000, 'credit' => 0],
                ['account_id' => $sales->id, 'debit' => 0, 'credit' => 1000],
            ],
            entryDate: now()->format('Y-m-d'),
        );
    }
}
