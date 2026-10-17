<?php

namespace Tests\Feature;

use App\Exceptions\ClosedFiscalYearException;
use App\Livewire\Comptabilite\ClotureExercice;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Services\AccountingEntryService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 10.6 (Sprint 10) — scénarios réels attendus par Document 01
 * §6.6 : solde des comptes de gestion équilibré par construction,
 * clôture qui verrouille effectivement les écritures, et blocage
 * serveur systématique de toute écriture rétroactive sur un exercice
 * clos (point 4).
 */
class ClotureExerciceTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // Ticket S2 : les étapes de clôture exigent désormais `close-fiscal-year`.
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $comptable = \App\Models\User::create([
            'name' => 'Comptable', 'username' => 'compta-cloture', 'email' => 'compta-cloture@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $comptable->assignRole('comptable');
        $this->actingAs($comptable);
    }

    private function account(string $code, string $label, int $class): ChartOfAccount
    {
        return ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $class, 'is_active' => true]);
    }

    public function test_full_closure_workflow_locks_entries_and_opens_next_year(): void
    {
        $year = FiscalYear::create([
            'year' => 2026,
            'start_date' => '2026-01-01',
            'end_date' => '2026-12-31',
            'status' => 'ouvert',
        ]);

        $this->account('131', 'Résultat - Bénéfice', 1);
        $this->account('139', 'Résultat - Perte', 1);
        $capital = $this->account('101', 'Capital', 1);
        $treasury = $this->account('531', 'Caisse', 5);
        $sales = $this->account('701', 'Ventes', 7);
        $expense = $this->account('601', 'Achats', 6);

        $service = app(AccountingEntryService::class);
        $service->recordManual($treasury->id, $capital->id, 1_000_000, '2026-03-01');
        $service->recordManual($treasury->id, $sales->id, 300_000, '2026-03-02');
        $service->recordManual($expense->id, $treasury->id, 120_000, '2026-03-03');

        $component = Livewire::test(ClotureExercice::class)
            ->set('selectedYear', '2026');

        // Résultat provisoire avant clôture = Produits - Charges = 300000 - 120000.
        $this->assertEquals(180000.0, $component->instance()->kpis['resultat']);
        $this->assertEquals(2, $component->instance()->kpis['comptes_a_solder']); // 701 et 601

        // Étape 2 : solde des comptes de gestion — après clôture, ces
        // comptes sont ramenés à zéro (débit=crédit), donc ils
        // disparaissent des "comptes à solder".
        $component->call('soldeComptesGestion');
        $this->assertEquals(0, $component->instance()->kpis['comptes_a_solder']);

        // Étape 3 : clôture réelle.
        $component->call('confirmCloture');

        $year->refresh();
        $this->assertEquals('cloture', $year->status);
        $this->assertNotNull($year->closed_at);

        $lockedCount = AccountingEntry::where('fiscal_year_id', $year->id)->where('is_locked', false)->count();
        $this->assertEquals(0, $lockedCount, "Toutes les écritures de l'exercice clôturé doivent être verrouillées.");

        $this->assertDatabaseHas('fiscal_years', ['year' => 2027, 'status' => 'ouvert']);
    }

    public function test_posting_into_a_closed_fiscal_year_is_rejected_server_side(): void
    {
        FiscalYear::create([
            'year' => 2025,
            'start_date' => '2025-01-01',
            'end_date' => '2025-12-31',
            'status' => 'cloture',
            'closed_at' => now(),
        ]);

        $treasury = $this->account('531', 'Caisse', 5);
        $sales = $this->account('701', 'Ventes', 7);

        $this->expectException(ClosedFiscalYearException::class);

        app(AccountingEntryService::class)->recordManual($treasury->id, $sales->id, 5000, '2025-06-15');
    }
}
