<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\GrandLivre;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Services\AccountingEntryService;
use App\Services\FinancialReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.1 (Sprint 14) — Grand Livre.
 *
 * Le jeu de données reproduit exactement celui écrit en dur dans
 * `grand-livre.html` pour le compte 531 (solde d'ouverture 338 000, quatre
 * mouvements du 13 au 15/07), dont le prototype documente lui-même le
 * résultat attendu : « Caisse 185 000 », chiffre déjà publié dans
 * `rapport-bilan.html`. Le test vérifie donc une valeur métier réelle et
 * recoupée, pas une valeur inventée pour l'occasion.
 */
class GrandLivreTest extends TestCase
{
    use RefreshDatabase;

    private function account(string $code, string $label, int $class): ChartOfAccount
    {
        return ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $class, 'is_active' => true]);
    }

    /** Jeu de données commun : renvoie [531, 601, 701]. */
    private function seedLedger(): array
    {
        FiscalYear::create([
            'year' => 2026,
            'start_date' => '2026-01-01',
            'end_date' => '2026-12-31',
            'status' => 'ouvert',
        ]);

        $caisse = $this->account('531', 'Caisse', 5);
        $achats = $this->account('601', 'Achats de marchandises', 6);
        $ventes = $this->account('701', 'Ventes de produits', 7);

        $service = app(AccountingEntryService::class);

        // Antérieur à la période : constitue le solde d'ouverture.
        $service->recordManual($caisse->id, $ventes->id, 338_000, '2026-06-30', 'OD-2026-0001 — Report ouverture caisse');

        // Les 4 mouvements du prototype, dans le même ordre.
        $service->recordManual($achats->id, $caisse->id, 162_800, '2026-07-13', 'OD-2026-0510 — Règlement salaire');
        $service->recordManual($achats->id, $caisse->id, 185_000, '2026-07-14', 'OD-2026-0511 — Achat aliment ponte');
        $service->recordManual($caisse->id, $ventes->id, 32_000, '2026-07-15', 'OD-2026-0512 — Vente POS #V-2026-884');
        $service->recordManual($caisse->id, $ventes->id, 162_800, '2026-07-15', 'OD-2026-0509 — Vente comptant divers');

        // Hors période : ne doit jamais peser sur les totaux affichés.
        $service->recordManual($caisse->id, $ventes->id, 999_999, '2026-08-01', 'OD-2026-0999 — Hors période');

        return [$caisse, $achats, $ventes];
    }

    public function test_running_balance_of_a_debit_nature_account_matches_the_published_bilan(): void
    {
        [$caisse] = $this->seedLedger();

        $ledger = app(FinancialReportService::class)->grandLivre($caisse->id, '2026-07-01', '2026-07-15');

        $this->assertTrue($ledger['is_debit_nature']);
        $this->assertEquals(338_000.0, $ledger['opening_balance']);
        $this->assertCount(4, $ledger['lines']);
        $this->assertEquals(194_800.0, $ledger['total_debit']);
        $this->assertEquals(347_800.0, $ledger['total_credit']);

        // Solde progressif attendu, ligne à ligne.
        $this->assertEquals(
            [175_200.0, -9_800.0, 22_200.0, 185_000.0],
            array_column($ledger['lines'], 'running_balance')
        );

        // Valeur métier recoupée avec `rapport-bilan.html` : Caisse 185 000.
        $this->assertEquals(185_000.0, $ledger['closing_balance']);
    }

    public function test_credit_nature_account_uses_the_opposite_sign(): void
    {
        [, , $ventes] = $this->seedLedger();

        $ledger = app(FinancialReportService::class)->grandLivre($ventes->id, '2026-07-01', '2026-07-15');

        $this->assertFalse($ledger['is_debit_nature']);
        $this->assertEquals(338_000.0, $ledger['opening_balance']);
        // Créditeur : crédit - débit, jamais l'inverse.
        $this->assertEquals(532_800.0, $ledger['closing_balance']);
    }

    /**
     * Le prototype tranchait le sens naturel via deux listes de codes en dur.
     * La règle dérivée de la classe SYSCOHADA doit reproduire exactement son
     * classement pour la classe 4, seul cas ambigu.
     */
    public function test_class_4_accounts_split_by_prefix(): void
    {
        $clients = $this->account('411', 'Clients', 4);
        $fournisseurs = $this->account('401', 'Fournisseurs', 4);

        $reports = app(FinancialReportService::class);

        $this->assertTrue($reports->grandLivre($clients->id, '2026-07-01', '2026-07-15')['is_debit_nature']);
        $this->assertFalse($reports->grandLivre($fournisseurs->id, '2026-07-01', '2026-07-15')['is_debit_nature']);
    }

    public function test_opening_balance_is_recomputed_when_the_period_changes(): void
    {
        [$caisse] = $this->seedLedger();

        $ledger = app(FinancialReportService::class)->grandLivre($caisse->id, '2026-07-14', '2026-07-15');

        // L'ouverture au 14/07 absorbe le mouvement du 13/07.
        $this->assertEquals(175_200.0, $ledger['opening_balance']);
        $this->assertCount(3, $ledger['lines']);
        // Le solde final ne dépend pas de la borne basse choisie.
        $this->assertEquals(185_000.0, $ledger['closing_balance']);
    }

    public function test_search_filters_server_side_and_totals_follow(): void
    {
        [$caisse] = $this->seedLedger();

        $ledger = app(FinancialReportService::class)->grandLivre($caisse->id, '2026-07-01', '2026-07-15', 'aliment');

        $this->assertCount(1, $ledger['lines']);
        $this->assertEquals(0.0, $ledger['total_debit']);
        $this->assertEquals(185_000.0, $ledger['total_credit']);
        $this->assertEquals('Achat aliment ponte', $ledger['lines'][0]['label']);
        $this->assertEquals('OD-2026-0511', $ledger['lines'][0]['reference']);
    }

    public function test_unknown_account_returns_a_neutral_ledger(): void
    {
        $ledger = app(FinancialReportService::class)->grandLivre('', '2026-07-01', '2026-07-15');

        $this->assertNull($ledger['account']);
        $this->assertSame([], $ledger['lines']);
        $this->assertEquals(0.0, $ledger['closing_balance']);
    }

    public function test_component_renders_and_defaults_to_the_caisse_account(): void
    {
        [$caisse] = $this->seedLedger();

        Livewire::test(GrandLivre::class)
            ->assertSet('accountId', $caisse->id)   // le prototype ouvre sur 531
            ->assertOk()
            ->assertSee('Grand Livre')
            ->assertSee('Solde Progressif');
    }

    public function test_component_recomputes_when_the_account_changes(): void
    {
        [$caisse, , $ventes] = $this->seedLedger();

        $component = Livewire::test(GrandLivre::class)
            ->set('startDate', '2026-07-01')
            ->set('endDate', '2026-07-15')
            ->set('accountId', $caisse->id);

        $this->assertEquals(185_000.0, $component->instance()->ledger['closing_balance']);

        $component->set('accountId', $ventes->id);

        $this->assertEquals(532_800.0, $component->instance()->ledger['closing_balance']);
    }
}
