<?php

namespace Tests\Feature;

use App\Livewire\Achats\SaisieDepenses;
use App\Livewire\Comptabilite\ClotureExercice;
use App\Livewire\RH\GestionPaie;
use App\Livewire\Stocks\GestionStocks;
use App\Livewire\Ventes\PosInterface;
use App\Models\ChartOfAccount;
use App\Models\Employee;
use App\Models\Expense;
use App\Models\FiscalYear;
use App\Models\Payslip;
use App\Models\Sale;
use App\Models\StockMovement;
use App\Services\AccountingEntryService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket EX5 (PRD exercices comptables, EF6) — PLUS AUCUNE ERREUR 500 LIÉE AUX EXERCICES.
 *
 * Constat du 20/10/2026 : `NoOpenFiscalYearException` et `ClosedFiscalYearException` n'étaient pas rattrapées par la
 * saisie des dépenses, la vente du jour en caisse, la paie, l'ajustement de stock ni la clôture : l'utilisateur voyait
 * une page d'erreur, et une écriture de stock pouvait survivre sans sa perte comptabilisée.
 *
 * Décor : 2025 et 2026 encore ouverts le 05/01/2027 — deux exercices ouverts, donc 2027 ne peut pas s'ouvrir (R2) et
 * plus rien ne couvre le jour. Chaque écran doit le DIRE (message R4 sous le champ ou en toast), sans rien écrire.
 * `Livewire::test` relève toute exception non rattrapée : un appel qui aboutit prouve l'absence d'erreur 500.
 */
class ErreursExerciceSans500Test extends TestCase
{
    use PreparationExercices;
    use RefreshDatabase;

    private const AUCUN_05_01 = "Aucun exercice comptable ne couvre le 05/01/2027. Ouvrez l'exercice 2027 (Comptabilité › Clôture d'exercice).";

    protected function setUp(): void
    {
        parent::setUp();

        $this->preparerDecor('2027-01-05 09:30:00');
        $this->exercice(2025);
        $this->exercice(2026);
        $this->stockDeMais(10, '2026-11-02 08:00:00');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_la_depense_du_jour_affiche_le_motif_sous_la_date(): void
    {
        $this->assertErreurSousLeChamp(
            Livewire::test(SaisieDepenses::class)
                ->call('nouvelleDepense')
                ->set('expenseDate', '2027-01-05')
                ->set('treasuryAccountId', $this->caisse->id)
                ->set('lines.0.label', 'Facture SBEE')
                ->set('lines.0.chargeAccountId', \App\Models\ChartOfAccount::where('code', '605')->value('id') ?? \App\Models\ChartOfAccount::create(['code' => '605', 'label' => 'Énergie', 'class' => 6, 'is_active' => true])->id)
                ->set('lines.0.amount', '25000')
                ->call('submitExpense'),
            'expenseDate',
            self::AUCUN_05_01,
        );

        $this->assertSame(0, Expense::count());
        $this->assertEquals(5_000_000, $this->caisse->fresh()->balance);
    }

    public function test_la_vente_du_jour_en_caisse_affiche_le_motif(): void
    {
        $attendu = 'Vente refusée : aucun exercice comptable ne couvre le 05/01/2027. '
            ."Ouvrez l'exercice 2027 (Comptabilité › Clôture d'exercice).";

        $pos = Livewire::test(PosInterface::class)
            ->set('paymentMode', 'especes')
            ->set('cart', [[
                'product_id' => $this->mais->id, 'name' => $this->mais->name, 'unit' => 'sac',
                'qty' => 1, 'montant' => 20_000, 'lot_id' => null, 'lot_code' => null,
            ]])
            ->call('validateSale')
            ->assertDispatched('toast', message: $attendu, type: 'error');

        $this->assertSame($attendu, $pos->errors()->first('dateVente'));
        $this->assertSame(0, Sale::count());
        $this->assertEquals(10, $this->mais->fresh()->stock_qty, 'la transaction annulée ne laisse aucune sortie de stock');
    }

    public function test_la_paie_affiche_le_motif(): void
    {
        $employe = Employee::create([
            'first_name' => 'Kossi', 'last_name' => 'ADJOVI', 'phone' => '+22997222222',
            'base_salary' => 100_000, 'hire_date' => '2025-01-06', 'is_active' => true,
        ]);

        Livewire::test(GestionPaie::class)
            ->set('periodMonth', '2027-01')
            ->call('validerReglement', $employe->id)
            ->assertDispatched('toast', message: self::AUCUN_05_01, type: 'error');

        $this->assertSame(0, Payslip::count());
        $this->assertEquals(5_000_000, $this->caisse->fresh()->balance);
    }

    /** Un manquant d'inventaire (perte au PMP, D 657 / C 601) : le stock ne bouge pas sans sa perte. */
    public function test_l_ajustement_de_stock_affiche_le_motif_et_n_ecrit_rien(): void
    {
        Livewire::test(GestionStocks::class)
            ->set('adjProductId', $this->mais->id)
            ->set('adjPhysical', 7)
            ->call('validateAdjustment')
            ->assertDispatched('toast', message: self::AUCUN_05_01, type: 'error');

        $this->assertEquals(10, $this->mais->fresh()->stock_qty);
        $this->assertSame(0, StockMovement::where('reference_type', 'adjustment')->count());
    }

    public function test_la_cloture_affiche_le_motif_d_un_a_nouveau_desequilibre(): void
    {
        $hao = ChartOfAccount::create(['code' => '81', 'label' => 'Valeurs comptables des cessions', 'class' => 8, 'is_active' => true]);
        FiscalYear::where('year', 2025)->update(['status' => 'cloture']);
        app(AccountingEntryService::class)->recordManual($hao->id, $this->comptes['531']->id, 50_000, '2026-06-30');

        Livewire::test(ClotureExercice::class)
            ->set('selectedYear', '2026')
            ->call('confirmStep1')
            ->call('soldeComptesGestion')
            ->call('confirmCloture')
            ->assertDispatched('toast', type: 'error');

        $this->assertSame('ouvert', FiscalYear::where('year', 2026)->value('status'));
    }
}
