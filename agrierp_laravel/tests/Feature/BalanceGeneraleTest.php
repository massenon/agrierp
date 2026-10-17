<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\BalanceGenerale;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Services\AccountingEntryService;
use App\Services\FinancialReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.5 (Sprint 14) — Balance Générale.
 *
 * La propriété qui compte vraiment sur cet écran est l'ÉQUILIBRE : toute
 * écriture étant équilibrée par construction (`AccountingEntryService`), la
 * somme des soldes finaux débiteurs doit égaler celle des soldes créditeurs,
 * quel que soit le mélange de comptes et de périodes. C'est ce que
 * l'utilisateur vient vérifier avant une clôture.
 */
class BalanceGeneraleTest extends TestCase
{
    use RefreshDatabase;

    private function account(string $code, string $label, int $class): ChartOfAccount
    {
        return ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $class, 'is_active' => true]);
    }

    private function seedFiscalYear(): FiscalYear
    {
        return FiscalYear::create([
            'year' => 2026,
            'start_date' => '2026-01-01',
            'end_date' => '2026-12-31',
            'status' => 'ouvert',
        ]);
    }

    public function test_opening_movements_and_final_balance_split_correctly(): void
    {
        $this->seedFiscalYear();

        $caisse = $this->account('531', 'Caisse', 5);
        $ventes = $this->account('701', 'Ventes de produits', 7);
        $achats = $this->account('601', 'Achats de marchandises', 6);

        $service = app(AccountingEntryService::class);

        // Avant la période -> solde d'ouverture.
        $service->recordManual($caisse->id, $ventes->id, 338_000, '2026-06-30', 'OD-2026-0001 — Ouverture');

        // Dans la période : la Caisse est mouvementée DANS LES DEUX SENS.
        $service->recordManual($achats->id, $caisse->id, 185_000, '2026-07-14', 'OD-2026-0511 — Achat aliment');
        $service->recordManual($caisse->id, $ventes->id, 32_000, '2026-07-15', 'OD-2026-0512 — Vente POS');

        $balance = app(FinancialReportService::class)->balanceGenerale('2026-07-01', '2026-07-31');

        $rows = collect($balance['rows'])->keyBy('code');

        // Caisse : ouverture 338 000 au débit (solde NET, une seule colonne)…
        $this->assertEquals(338_000.0, $rows['531']['opening_debit']);
        $this->assertEquals(0.0, $rows['531']['opening_credit']);

        // …mais les mouvements de la période restent des cumuls BRUTS des deux
        // côtés — c'est tout l'intérêt des colonnes Mouvements.
        $this->assertEquals(32_000.0, $rows['531']['period_debit']);
        $this->assertEquals(185_000.0, $rows['531']['period_credit']);

        // Solde final = (338 000 + 32 000) − 185 000 = 185 000, au débit.
        $this->assertEquals(185_000.0, $rows['531']['final_debit']);
        $this->assertEquals(0.0, $rows['531']['final_credit']);

        // Ventes (créditeur) : 338 000 d'ouverture + 32 000 sur la période.
        $this->assertEquals(338_000.0, $rows['701']['opening_credit']);
        $this->assertEquals(370_000.0, $rows['701']['final_credit']);
    }

    public function test_the_balance_stays_balanced_whatever_the_mix_of_accounts(): void
    {
        $this->seedFiscalYear();

        $capital = $this->account('101', 'Capital', 1);
        $batiments = $this->account('221', 'Bâtiments', 2);
        $stocks = $this->account('311', 'Stocks', 3);
        $clients = $this->account('411', 'Clients', 4);
        $caisse = $this->account('531', 'Caisse', 5);
        $achats = $this->account('601', 'Achats', 6);
        $ventes = $this->account('701', 'Ventes', 7);

        $service = app(AccountingEntryService::class);
        $service->recordManual($caisse->id, $capital->id, 1_000_000, '2026-01-05', 'OD-2026-0001 — Apport');
        $service->recordManual($batiments->id, $caisse->id, 400_000, '2026-02-10', 'OD-2026-0002 — Bâtiment');
        $service->recordManual($stocks->id, $caisse->id, 120_000, '2026-03-01', 'OD-2026-0003 — Stock');
        $service->recordManual($clients->id, $ventes->id, 250_000, '2026-07-02', 'OD-2026-0004 — Vente à crédit');
        $service->recordManual($achats->id, $caisse->id, 90_000, '2026-07-09', 'OD-2026-0005 — Achat');

        // Sur l'exercice complet comme sur le seul mois de juillet.
        foreach ([['2026-01-01', '2026-12-31'], ['2026-07-01', '2026-07-31']] as [$start, $end]) {
            $balance = app(FinancialReportService::class)->balanceGenerale($start, $end);

            $this->assertTrue(
                $balance['is_balanced'],
                "Balance déséquilibrée sur {$start} → {$end} : écart de {$balance['ecart']}."
            );
            $this->assertEquals(0.0, $balance['ecart']);

            // Recalcul indépendant du total, sans repasser par les agrégats du service.
            $sommeDebits = array_sum(array_column($balance['rows'], 'final_debit'));
            $sommeCredits = array_sum(array_column($balance['rows'], 'final_credit'));
            $this->assertEquals(round($sommeDebits, 2), $balance['total_final_debit']);
            $this->assertEquals(round($sommeCredits, 2), $balance['total_final_credit']);
            $this->assertEquals(round($sommeDebits, 2), round($sommeCredits, 2));
        }
    }

    /**
     * Le point de conception à ne pas inverser : un compte en anomalie (solde
     * de sens opposé à sa nature) doit rester VISIBLE, dans la colonne
     * correspondant au signe réel de son solde.
     */
    public function test_an_account_against_its_natural_side_stays_visible(): void
    {
        $this->seedFiscalYear();

        $caisse = $this->account('531', 'Caisse', 5);       // débiteur par nature
        $ventes = $this->account('701', 'Ventes', 7);

        // Écriture qui met la Caisse en position CRÉDITRICE (anomalie réelle
        // qu'une balance doit révéler, jamais masquer).
        app(AccountingEntryService::class)
            ->recordManual($ventes->id, $caisse->id, 75_000, '2026-07-10', 'OD-2026-0009 — Anomalie');

        $balance = app(FinancialReportService::class)->balanceGenerale('2026-07-01', '2026-07-31');
        $rows = collect($balance['rows'])->keyBy('code');

        $this->assertArrayHasKey('531', $rows->all(), 'Le compte en anomalie ne doit jamais disparaître de la balance.');
        $this->assertEquals(75_000.0, $rows['531']['final_credit']);
        $this->assertEquals(0.0, $rows['531']['final_debit']);
        $this->assertTrue($balance['is_balanced']);
    }

    public function test_accounts_without_any_movement_are_left_out(): void
    {
        $this->seedFiscalYear();

        $caisse = $this->account('531', 'Caisse', 5);
        $ventes = $this->account('701', 'Ventes', 7);
        $this->account('681', 'Dotations aux amortissements', 6);   // jamais mouvementé

        app(AccountingEntryService::class)
            ->recordManual($caisse->id, $ventes->id, 10_000, '2026-07-10', 'OD-2026-0010 — Vente');

        $balance = app(FinancialReportService::class)->balanceGenerale('2026-07-01', '2026-07-31');
        $codes = array_column($balance['rows'], 'code');

        $this->assertContains('531', $codes);
        $this->assertNotContains('681', $codes);
    }

    public function test_component_renders_and_switches_period(): void
    {
        $this->seedFiscalYear();

        $caisse = $this->account('531', 'Caisse', 5);
        $ventes = $this->account('701', 'Ventes', 7);
        app(AccountingEntryService::class)
            ->recordManual($caisse->id, $ventes->id, 10_000, now()->format('Y-m-d'), 'OD-2026-0011 — Vente du jour');

        $component = Livewire::test(BalanceGenerale::class)
            ->assertOk()
            ->assertSee('Balance Générale')
            ->assertSee('Solde Ouverture');

        $this->assertTrue($component->instance()->balance['is_balanced']);

        $component->set('periode', 'exercice');

        $this->assertEquals(
            ['2026-01-01', '2026-12-31'],
            $component->instance()->periodBounds(),
            "L'option Exercice doit suivre l'exercice réellement ouvert, pas l'année civile supposée."
        );
    }
}
