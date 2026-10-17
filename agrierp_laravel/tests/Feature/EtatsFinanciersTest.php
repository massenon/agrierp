<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\EtatsFinanciers;
use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Services\AccountingEntryService;
use App\Services\FinancialReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.6 (Sprint 14) — États Financiers.
 *
 * Deux exigences structurelles sont verrouillées ici :
 *  1. le Résultat Net du Compte de Résultat est STRICTEMENT identique à celui
 *     du Bilan — exigence explicite du prototype, garantie par construction ;
 *  2. le contrôle de cohérence du TAFIRE est réellement FALSIFIABLE — le
 *     prototype le rendait toujours vrai par pure algèbre.
 */
class EtatsFinanciersTest extends TestCase
{
    use RefreshDatabase;

    private function account(string $code, string $label, int $class): ChartOfAccount
    {
        return ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $class, 'is_active' => true]);
    }

    private function fiscalYear(): FiscalYear
    {
        return FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);
    }

    /** Jeu d'écritures couvrant les 7 classes. */
    private function seedLedger(): void
    {
        $this->fiscalYear();

        $capital = $this->account('101', 'Capital', 1);
        $batiments = $this->account('221', 'Bâtiments', 2);
        $amort = $this->account('281', 'Amortissements cumulés', 2);
        $stocks = $this->account('311', 'Stocks', 3);
        $clients = $this->account('411', 'Clients', 4);
        $fournisseurs = $this->account('401', 'Fournisseurs', 4);
        $caisse = $this->account('531', 'Caisse', 5);
        $achats = $this->account('601', 'Achats', 6);
        $autres = $this->account('65', 'Autres charges de gestion', 6);
        $personnel = $this->account('661', 'Charges de personnel', 6);
        $dotations = $this->account('681', 'Dotations aux amortissements', 6);
        $ventes = $this->account('701', 'Ventes', 7);

        $s = app(AccountingEntryService::class);
        $d = fn (int $days) => now()->startOfYear()->addDays($days)->format('Y-m-d');

        $s->recordManual($caisse->id, $capital->id, 4_500_000, $d(1), 'OD-0001 — Apport en capital');
        $s->recordManual($batiments->id, $caisse->id, 2_400_000, $d(10), 'OD-0002 — Bâtiment');
        $s->recordManual($stocks->id, $fournisseurs->id, 612_000, $d(20), 'OD-0003 — Stock à crédit');
        $s->recordManual($caisse->id, $ventes->id, 4_650_000, $d(30), 'OD-0004 — Ventes comptant');
        $s->recordManual($clients->id, $ventes->id, 95_000, $d(35), 'OD-0005 — Vente à crédit');
        $s->recordManual($achats->id, $caisse->id, 1_850_000, $d(40), 'OD-0006 — Achats');
        $s->recordManual($personnel->id, $caisse->id, 890_000, $d(45), 'OD-0007 — Salaires');
        $s->recordManual($dotations->id, $amort->id, 380_000, $d(50), 'OD-0008 — Dotation');
        $s->recordManual($autres->id, $caisse->id, 290_000, $d(55), 'OD-0009 — Charges diverses');
    }

    public function test_net_result_is_strictly_identical_between_income_statement_and_balance_sheet(): void
    {
        $this->seedLedger();

        $reports = app(FinancialReportService::class);
        $asOf = now()->format('Y-m-d');

        $bilan = $reports->bilan($asOf);
        $resultat = $reports->compteResultat($asOf);

        $this->assertEquals(
            $bilan['resultat'],
            $resultat['resultat_net'],
            'Le Résultat Net doit être strictement identique au Bilan et au Compte de Résultat.'
        );

        // Cascade SYSCOHADA vérifiée pas à pas, recalculée indépendamment.
        $this->assertEquals(4_745_000.0, $resultat['ventes']);   // 4 650 000 comptant + 95 000 à crédit
        $this->assertEquals(1_850_000.0, $resultat['achats']);
        $this->assertEquals(2_895_000.0, $resultat['marge_commerciale']);   // 4 745 000 − 1 850 000
        $this->assertEquals(890_000.0, $resultat['charges_personnel']);
        $this->assertEquals(2_005_000.0, $resultat['ebe']);                  // 2 895 000 − 890 000
        $this->assertEquals(380_000.0, $resultat['dotations']);
        $this->assertEquals(1_625_000.0, $resultat['resultat_exploitation']);// 2 005 000 − 380 000
        $this->assertEquals(290_000.0, $resultat['autres_charges']);
        $this->assertEquals(1_335_000.0, $resultat['resultat_net']);         // 1 625 000 − 290 000

        $this->assertTrue($bilan['is_balanced']);
    }

    /**
     * Aucun compte de classe 6 ne doit pouvoir « tomber » hors de la cascade :
     * un compte de charge non prévu (ni 60/65/66/67/68) doit être absorbé par
     * la ligne « autres charges », donc rester dans le Résultat Net.
     */
    public function test_an_unforeseen_charge_account_is_absorbed_not_lost(): void
    {
        $this->seedLedger();

        $exceptionnelles = $this->account('657', 'Charges exceptionnelles', 6);
        $caisse = ChartOfAccount::where('code', '531')->firstOrFail();

        app(AccountingEntryService::class)
            ->recordManual($exceptionnelles->id, $caisse->id, 50_000, now()->format('Y-m-d'), 'OD-0010 — Perte inventaire');

        $reports = app(FinancialReportService::class);
        $asOf = now()->format('Y-m-d');

        $this->assertEquals(340_000.0, $reports->compteResultat($asOf)['autres_charges']);   // 290 000 + 50 000
        $this->assertEquals(1_285_000.0, $reports->compteResultat($asOf)['resultat_net']);   // 1 335 000 − 50 000
        $this->assertEquals(
            $reports->bilan($asOf)['resultat'],
            $reports->compteResultat($asOf)['resultat_net'],
            'Un compte de charge imprévu ne doit jamais faire diverger les deux écrans.'
        );
    }

    public function test_the_cash_flow_statement_reconciles_with_the_balance_sheet(): void
    {
        $this->seedLedger();

        $tafire = app(FinancialReportService::class)->tafire(
            now()->startOfYear()->format('Y-m-d'),
            now()->format('Y-m-d')
        );

        $this->assertTrue(
            $tafire['is_coherent'],
            "TAFIRE incohérent : écart de {$tafire['ecart']} entre la clôture dérivée des flux et celle du Bilan."
        );
        $this->assertEquals(0.0, $tafire['ecart']);

        // La clôture est DÉRIVÉE des flux, pas recopiée depuis le Bilan…
        $this->assertEquals(
            round($tafire['tresorerie_ouverture'] + $tafire['variation_tresorerie'], 2),
            $tafire['tresorerie_cloture']
        );
        // …et coïncide néanmoins avec la trésorerie réelle du Bilan.
        $this->assertEquals($tafire['tresorerie_cloture_bilan'], $tafire['tresorerie_cloture']);
    }

    /**
     * LE POINT CRUCIAL : le prototype définissait
     *   ouverture = clôture − variation ; clôture = ouverture + variation
     * rendant le contrôle vrai par pure algèbre. Ici il doit réellement
     * pouvoir échouer — démontré en injectant une écriture DÉSÉQUILIBRÉE
     * directement en base (ce que le service refuserait, précisément).
     */
    public function test_the_coherence_check_can_actually_fail(): void
    {
        $this->seedLedger();

        $caisse = ChartOfAccount::where('code', '531')->firstOrFail();
        $year = FiscalYear::firstOrFail();

        $entry = AccountingEntry::create([
            'fiscal_year_id' => $year->id,
            'entry_date' => now()->format('Y-m-d'),
            'reference' => 'OD-CORROMPUE — écriture déséquilibrée',
            'source_type' => 'manual',
            'is_active' => true,
        ]);
        // Une seule ligne : débit sans contrepartie.
        AccountingEntryLine::create([
            'entry_id' => $entry->id,
            'account_id' => $caisse->id,
            'debit' => 100_000,
            'credit' => 0,
        ]);

        $tafire = app(FinancialReportService::class)->tafire(
            now()->startOfYear()->format('Y-m-d'),
            now()->format('Y-m-d')
        );

        $this->assertFalse(
            $tafire['is_coherent'],
            'Le contrôle de cohérence doit détecter une écriture déséquilibrée — sinon il ne vérifie rien.'
        );
        $this->assertEquals(100_000.0, abs($tafire['ecart']));
    }

    public function test_component_renders_each_of_the_four_tabs(): void
    {
        $this->seedLedger();

        $component = Livewire::test(EtatsFinanciers::class)
            ->assertOk()
            ->assertSee('États Financiers')
            ->assertSee('Actif (Emplois)');

        $component->call('switchTab', 'resultat')->assertSee('MARGE COMMERCIALE');
        $component->call('switchTab', 'tafire')->assertSee('Tableau des Flux de Trésorerie');
        $component->call('switchTab', 'notes')->assertSee('Note 5 — Engagements Hors Bilan');

        // Onglet inconnu -> repli sûr sur Bilan, jamais un onglet vide.
        $component->call('switchTab', 'inexistant')->assertSet('tab', 'bilan');
    }
}
