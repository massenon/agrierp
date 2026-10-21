<?php

namespace Tests\Feature;

use App\Livewire\RH\GestionPaie;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\Employee;
use App\Models\FiscalYear;
use App\Models\Payslip;
use App\Models\Permission;
use App\Models\Role;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\FinancialReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.25 (Sprint 14) — cycle PAIE, jusqu'aux états financiers.
 *
 * Le point qui distingue une écriture juste d'une écriture qui équilibre par
 * hasard : la charge portée au débit doit être le salaire RÉELLEMENT DÛ, pas
 * le net versé. La retenue CNSS est prélevée sur le salarié mais reste due à
 * l'organisme — la comptabiliser en dette (431) et non en non-dépense.
 */
class CyclePaieComptableTest extends TestCase
{
    use RefreshDatabase;

    private Employee $employe;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-rh', 'manage-rh'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('admin', 'web');
        $role->givePermissionTo(['view-rh', 'manage-rh']);

        $user = User::create([
            'name' => 'DG', 'email' => 'paie@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'),
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
            ['431', 'Sécurité sociale (CNSS)', 4],
            ['661', 'Charges de personnel', 6],
            // Ticket 14.38 — comptes de la paie béninoise.
            ['664', 'Charges sociales patronales', 6],
            ['4472', 'Impôt sur les traitements et salaires (ITS)', 4],
            ['4473', 'Versement patronal sur salaires (VPS)', 4],
        ] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }

        // Paramètres et barème : sans eux, ni ITS ni charges patronales.
        \App\Models\CompanySetting::create([
            'company_name' => 'FERME ÉCOLE OLOUWACHEGOUN',
            'vps_rate' => 4, 'cnss_employee_rate' => 3.6,
            'cnss_employer_pension_rate' => 6.4, 'cnss_employer_family_rate' => 9,
            'cnss_employer_risk_rate' => 2,
        ]);

        (new \Database\Seeders\IncomeTaxBracketsSeeder())->run();

        TreasuryAccount::create([
            'type' => 'caisse', 'label' => 'Caisse Principale',
            'account_code' => '531', 'balance' => 1_000_000, 'is_active' => true,
        ]);

        $this->employe = Employee::create([
            'first_name' => 'Kossi', 'last_name' => 'ADJOVI',
            'phone' => '+22997222222', 'base_salary' => 100_000,
            'hire_date' => now()->subYear()->format('Y-m-d'),
            'is_active' => true,
        ]);
    }

    private function reglerLaPaie(): void
    {
        Livewire::test(GestionPaie::class)->call('validerReglement', $this->employe->id);
    }

    /**
     * LE POINT CENTRAL : la charge est le salaire dû, la retenue est une dette.
     */
    /**
     * LE POINT CENTRAL : la charge portée au débit de 661 est le salaire
     * RÉELLEMENT DÛ, avant toute retenue — net + CNSS salariale + ITS.
     *
     * Sur 100 000 FCFA de brut (ticket 14.38) :
     *   CNSS salariale 3,6 %  ....  3 600   → net imposable 96 400
     *   ITS (barème)           ....  3 640   → (96 400 − 60 000) × 10 %
     *   NET VERSÉ              ....  92 760
     */
    public function test_the_charge_is_the_salary_due_not_the_net_paid(): void
    {
        $this->reglerLaPaie();

        $bulletin = Payslip::firstOrFail();
        $this->assertNotNull($bulletin->accounting_entry_id, 'La paie doit generer son ecriture.');

        $this->assertEquals(3_600, (float) $bulletin->cnss_deduction);
        $this->assertEquals(3_640, (float) $bulletin->its_deduction, 'ITS progressif sur le net imposable.');
        $this->assertEquals(92_760, (float) $bulletin->net_salary);

        $ecriture = AccountingEntry::with('lines.account')->findOrFail($bulletin->accounting_entry_id);
        $parCompte = $ecriture->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertEquals(100_000, (float) $parCompte['661']->debit, 'La charge est le salaire du, pas le net.');
        $this->assertEquals(3_640, (float) $parCompte['4472']->credit, 'L impot retenu est une dette envers le Tresor.');
        $this->assertEquals(92_760, (float) $parCompte['531']->credit, 'Seul le net sort de la tresorerie.');
        $this->assertEquals($ecriture->total_debit, $ecriture->total_credit);
    }

    /**
     * ⚠️ LES CHARGES PATRONALES NE TOUCHENT PAS LE NET DU SALARIÉ.
     *
     * Sur 100 000 FCFA de brut : VPS 4 % + CNSS employeur (6,4 % pensions,
     * 9 % prestations familiales, 2 % risques) = 21 400 FCFA versés EN PLUS.
     * Les omettre — ce que faisait l'application — sous-déclarait le coût réel
     * du travail de 21,4 %.
     */
    public function test_employer_charges_add_to_the_cost_without_touching_the_net(): void
    {
        $this->reglerLaPaie();

        $bulletin = Payslip::firstOrFail();

        $this->assertEquals(4_000, (float) $bulletin->vps_employer);
        $this->assertEquals(6_400, (float) $bulletin->cnss_employer_pension);
        $this->assertEquals(9_000, (float) $bulletin->cnss_employer_family);
        $this->assertEquals(2_000, (float) $bulletin->cnss_employer_risk);

        // Le net reste celui du salarié : les charges patronales n'y touchent pas.
        $this->assertEquals(92_760, (float) $bulletin->net_salary);

        $parCompte = AccountingEntry::with('lines.account')
            ->findOrFail($bulletin->accounting_entry_id)
            ->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertEquals(21_400, (float) $parCompte['664']->debit, 'Charge patronale totale.');
        $this->assertEquals(4_000, (float) $parCompte['4473']->credit, 'Dette de VPS envers le Tresor.');
        $this->assertEquals(21_000, (float) $parCompte['431']->credit,
            'CNSS totale due : 3 600 salariale + 17 400 patronale.');
    }

    /** Les charges de personnel apparaissent enfin au Compte de Résultat. */
    public function test_payroll_finally_appears_in_the_income_statement(): void
    {
        $this->reglerLaPaie();

        $reports = app(FinancialReportService::class);
        $resultat = $reports->compteResultat(now()->format('Y-m-d'));

        // 100 000 de salaire dû + 21 400 de charges patronales.
        $this->assertEquals(121_400, $resultat['charges_personnel']);
        $this->assertEquals(-121_400, $resultat['resultat_net']);

        $this->assertTrue($reports->bilan(now()->format('Y-m-d'))['is_balanced']);
        $this->assertTrue(
            $reports->balanceGenerale(now()->startOfMonth()->format('Y-m-d'), now()->endOfMonth()->format('Y-m-d'))['is_balanced']
        );
    }

    /** Un même bulletin n'est jamais comptabilisé deux fois. */
    public function test_a_payslip_is_never_posted_twice(): void
    {
        $this->reglerLaPaie();

        app(\App\Actions\RecordPayrollAccountingEntryAction::class)->execute(Payslip::firstOrFail());

        $this->assertEquals(1, AccountingEntry::where('source_type', 'payroll')->count());
    }

    /** Le règlement reste unique : pas de double bulletin sur la même période. */
    public function test_settling_twice_creates_no_second_payslip(): void
    {
        $this->reglerLaPaie();
        $this->reglerLaPaie();

        $this->assertEquals(1, Payslip::count());
        $this->assertEquals(1, AccountingEntry::where('source_type', 'payroll')->count());
    }
}
