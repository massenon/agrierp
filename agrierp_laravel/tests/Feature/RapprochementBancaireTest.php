<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\RapprochementBancaire;
use App\Models\BankStatementLine;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Services\AccountingEntryService;
use App\Services\BankReconciliationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.8 (Sprint 14) — Rapprochement Bancaire.
 *
 * Le scénario reproduit celui du prototype : une opération passée au livre
 * mais pas encore débitée par la banque (chèque émis, « en instance ») et une
 * ligne du relevé pas encore saisie au livre (frais de tenue de compte,
 * « nouveau »). L'équation de rapprochement doit retomber sur zéro malgré ces
 * deux décalages — c'est exactement le service que rend cet écran.
 */
class RapprochementBancaireTest extends TestCase
{
    use RefreshDatabase;

    private ChartOfAccount $banque;

    private ChartOfAccount $contrepartie;

    protected function setUp(): void
    {
        parent::setUp();

        FiscalYear::create([
            'year' => 2026,
            'start_date' => '2026-01-01',
            'end_date' => '2026-12-31',
            'status' => 'ouvert',
        ]);

        $this->banque = ChartOfAccount::create(['code' => '521101', 'label' => 'Banque - Compte principal', 'class' => 5, 'is_active' => true]);
        $this->contrepartie = ChartOfAccount::create(['code' => '701', 'label' => 'Ventes', 'class' => 7, 'is_active' => true]);
        ChartOfAccount::create(['code' => '601', 'label' => 'Achats', 'class' => 6, 'is_active' => true]);
    }

    private function ecriture(float $montant, string $date, string $libelle): void
    {
        $service = app(AccountingEntryService::class);
        $achats = ChartOfAccount::where('code', '601')->firstOrFail();

        if ($montant >= 0) {
            // Encaissement : banque débitée.
            $service->recordManual($this->banque->id, $this->contrepartie->id, $montant, $date, 'OD-0001 — '.$libelle);
        } else {
            // Décaissement : banque créditée.
            $service->recordManual($achats->id, $this->banque->id, abs($montant), $date, 'OD-0002 — '.$libelle);
        }
    }

    private function ligneReleve(float $montant, string $date, string $libelle): void
    {
        BankStatementLine::create([
            'account_id' => $this->banque->id,
            'statement_date' => $date,
            'label' => $libelle,
            'amount' => $montant,
        ]);
    }

    public function test_the_reconciliation_balances_despite_timing_differences(): void
    {
        // Solde d'ouverture : une écriture antérieure à la période.
        $this->ecriture(2_318_500, '2026-06-20', 'Report ouverture');

        // Période : 25/06 au 01/07
        $this->ecriture(15_000, '2026-06-26', 'Virement client');           // pointé
        $this->ecriture(-8_500, '2026-06-28', 'Chèque fournisseur 00214');  // EN INSTANCE
        $this->ecriture(15_000, '2026-06-30', 'Dépôt espèces');             // pointé

        $this->ligneReleve(15_000, '2026-06-26', 'VIR RECU CLIENT GROSSISTE');
        $this->ligneReleve(-1_000, '2026-06-29', 'FRAIS TENUE DE COMPTE');  // NOUVEAU, pas au livre
        $this->ligneReleve(15_000, '2026-06-30', 'DEPOT ESPECES');

        $r = app(BankReconciliationService::class)
            ->reconcile($this->banque->id, '2026-06-25', '2026-07-01');

        $this->assertEquals(2_318_500.0, $r['opening_balance']);
        $this->assertEquals(2_340_000.0, $r['solde_livre']);      // 2 318 500 + 15 000 − 8 500 + 15 000
        $this->assertEquals(2_347_500.0, $r['solde_releve']);     // 2 318 500 + 15 000 − 1 000 + 15 000

        $this->assertEquals(-8_500.0, $r['en_instance'], 'Le chèque émis non débité doit rester en instance.');
        $this->assertEquals(-1_000.0, $r['nouveau_non_saisi'], 'Les frais bancaires non saisis doivent être isolés.');

        // 2 340 000 − (−8 500) + (−1 000) = 2 347 500 = solde relevé
        $this->assertEquals(0.0, $r['ecart']);
        $this->assertTrue($r['is_balanced']);
    }

    public function test_matching_flags_each_side_correctly(): void
    {
        $this->ecriture(15_000, '2026-06-26', 'Virement client');
        $this->ecriture(-8_500, '2026-06-28', 'Chèque fournisseur');
        $this->ligneReleve(15_000, '2026-06-27', 'VIR RECU');    // 1 jour d'écart -> apparié

        $r = app(BankReconciliationService::class)
            ->reconcile($this->banque->id, '2026-06-25', '2026-07-01');

        $ledger = collect($r['ledger']);
        $this->assertTrue($ledger->firstWhere('amount', 15_000.0)['is_matched']);
        $this->assertFalse($ledger->firstWhere('amount', -8_500.0)['is_matched']);
        $this->assertTrue($r['statement'][0]['is_matched']);
    }

    /** Au-delà de la tolérance, aucun appariement : deux opérations distinctes. */
    public function test_a_statement_line_too_far_apart_is_not_matched(): void
    {
        $this->ecriture(15_000, '2026-06-01', 'Virement client');
        $this->ligneReleve(15_000, '2026-06-30', 'VIR RECU');   // 29 jours -> hors tolérance

        $r = app(BankReconciliationService::class)
            ->reconcile($this->banque->id, '2026-06-01', '2026-06-30');

        $this->assertFalse($r['ledger'][0]['is_matched']);
        $this->assertFalse($r['statement'][0]['is_matched']);
    }

    /**
     * Deux encaissements identiques ne doivent JAMAIS être lettrés contre une
     * seule ligne de relevé — sinon un doublon réel passerait inaperçu.
     */
    public function test_one_statement_line_cannot_match_two_ledger_lines(): void
    {
        $this->ecriture(15_000, '2026-06-26', 'Virement A');
        $this->ecriture(15_000, '2026-06-27', 'Virement B');
        $this->ligneReleve(15_000, '2026-06-26', 'VIR RECU');   // une seule ligne au relevé

        $r = app(BankReconciliationService::class)
            ->reconcile($this->banque->id, '2026-06-25', '2026-07-01');

        $apparies = collect($r['ledger'])->where('is_matched', true)->count();

        $this->assertEquals(1, $apparies, 'Une seule des deux écritures peut être lettrée.');
        $this->assertEquals(15_000.0, $r['en_instance'], "L'écriture non lettrée doit apparaître en instance.");
    }

    public function test_csv_import_reads_real_lines_and_reports_unreadable_ones(): void
    {
        $csv = "date;libelle;montant\n"
            ."2026-06-26;VIR RECU CLIENT GROSSISTE;15 000\n"
            ."2026-06-29;FRAIS TENUE DE COMPTE;-1000,00\n"
            ."ligne;illisible\n"
            ."2026-06-30;DEPOT ESPECES;15000\n";

        $resultat = app(BankReconciliationService::class)->importCsv($this->banque->id, $csv);

        $this->assertEquals(3, $resultat['imported']);
        $this->assertEquals(1, $resultat['skipped'], 'Une ligne illisible doit être comptée, jamais avalée en silence.');

        $this->assertEquals(3, BankStatementLine::count());
        $this->assertEquals(-1_000.0, (float) BankStatementLine::where('label', 'FRAIS TENUE DE COMPTE')->value('amount'));
        $this->assertEquals(15_000.0, (float) BankStatementLine::where('label', 'VIR RECU CLIENT GROSSISTE')->value('amount'));
    }

    public function test_component_renders_with_real_treasury_accounts(): void
    {
        $this->ecriture(15_000, now()->format('Y-m-d'), 'Virement du jour');

        Livewire::test(RapprochementBancaire::class)
            ->assertOk()
            ->assertSee('Rapprochement Bancaire')
            ->assertSee('521101')                    // compte réel du plan, jamais 521 codé en dur
            ->assertSet('accountId', $this->banque->id);
    }
}
