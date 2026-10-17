<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\Bilan;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Services\AccountingEntryService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 10.5 (Sprint 10) — preuve réelle que l'équilibre Actif/Passif
 * tient PAR CONSTRUCTION (voir docblock de `Bilan::class`), pas par
 * coïncidence : plusieurs écritures manuelles de classes différentes
 * (immobilisation, trésorerie, capitaux, charges, produits) sont
 * enregistrées, puis le Bilan doit rester équilibré quel que soit le
 * mélange de comptes touchés.
 */
class BilanTest extends TestCase
{
    use RefreshDatabase;

    private function account(string $code, string $label, int $class): ChartOfAccount
    {
        return ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $class, 'is_active' => true]);
    }

    public function test_bilan_stays_balanced_across_a_mix_of_account_classes(): void
    {
        FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);

        $capital = $this->account('101', 'Capital', 1);
        $treasury = $this->account('531', 'Caisse', 5);
        $immo = $this->account('231', 'Bâtiments', 2);
        $sales = $this->account('701', 'Ventes', 7);
        $expense = $this->account('601', 'Achats', 6);
        $clients = $this->account('411', 'Clients', 4);
        $suppliers = $this->account('401', 'Fournisseurs', 4);

        $service = app(AccountingEntryService::class);

        // Apport de capital initial en trésorerie.
        $service->recordManual($treasury->id, $capital->id, 4_500_000, now()->format('Y-m-d'));
        // Achat d'un bâtiment payé en caisse.
        $service->recordManual($immo->id, $treasury->id, 2_400_000, now()->format('Y-m-d'));
        // Vente encaissée directement.
        $service->recordManual($treasury->id, $sales->id, 32_000, now()->format('Y-m-d'));
        // Vente à crédit à un client.
        $service->recordManual($clients->id, $sales->id, 95_000, now()->format('Y-m-d'));
        // Achat à crédit fournisseur.
        $service->recordManual($expense->id, $suppliers->id, 185_000, now()->format('Y-m-d'));

        $component = Livewire::test(Bilan::class)
            ->assertSet('asOfDate', now()->format('Y-m-d'))
            ->assertViewHas('title');

        $bilan = $component->instance()->bilan;

        $this->assertTrue($bilan['is_balanced'], 'Le Bilan doit rester équilibré quel que soit le mélange de classes de comptes touchées.');
        $this->assertEqualsWithDelta($bilan['total_actif'], $bilan['total_passif'], 0.01);
    }
}
