<?php

namespace Tests\Feature;

use App\Livewire\Parametres\BaremeIts;
use App\Models\CompanySetting;
use App\Models\Employee;
use App\Models\IncomeTaxBracket;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Services\PayrollCalculationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.39 (Sprint 14) — BARÈME ITS ÉDITABLE, RECALCUL AUTOMATIQUE,
 * VERROUILLAGE À L'ADMINISTRATEUR.
 *
 * Trois propriétés à tenir ensemble :
 *   1. le barème se modifie sans redéploiement ;
 *   2. toute modification se répercute IMMÉDIATEMENT sur les paies non réglées ;
 *   3. après la première édition, seul un administrateur peut y revenir.
 *
 * Et une cohérence à ne jamais laisser passer : un barème troué ou chevauchant
 * produit un impôt faux **sans lever la moindre erreur**.
 */
class BaremeItsEditableTest extends TestCase
{
    use RefreshDatabase;

    private User $comptable;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-parametres', 'view-rh', 'manage-rh'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }

        $roleComptable = Role::findOrCreate('comptable', 'web');
        $roleComptable->givePermissionTo(['view-parametres', 'view-rh', 'manage-rh']);

        $roleAdmin = Role::findOrCreate('admin', 'web');
        $roleAdmin->givePermissionTo(['view-parametres', 'view-rh', 'manage-rh']);

        $this->comptable = User::create([
            'name' => 'Christine KOUTON', 'email' => 'bareme-compta@olouwachegoun.bj', 'password' => bcrypt('AgriERP@2026'),
        ]);
        $this->comptable->assignRole($roleComptable);

        $this->admin = User::create([
            'name' => 'Directeur Général', 'email' => 'bareme-dg@olouwachegoun.bj', 'password' => bcrypt('AgriERP@2026'),
        ]);
        $this->admin->assignRole($roleAdmin);

        CompanySetting::create([
            'company_name' => 'FERME ÉCOLE OLOUWACHEGOUN',
            'cnss_employee_rate' => 3.6, 'vps_rate' => 4,
            'cnss_employer_pension_rate' => 6.4, 'cnss_employer_family_rate' => 9,
            'cnss_employer_risk_rate' => 2,
        ]);

        (new \Database\Seeders\IncomeTaxBracketsSeeder())->run();

        $this->actingAs($this->comptable);
    }

    /** @param  array<int, array{from: mixed, to: mixed, rate: mixed}>  $tranches */
    private function enregistrer(array $tranches, ?User $auteur = null)
    {
        $this->actingAs($auteur ?? $this->comptable);

        return Livewire::test(BaremeIts::class)
            ->set('tranches', array_map(fn ($t) => $t + ['id' => null], $tranches))
            ->call('enregistrer');
    }

    private function baremeValide(): array
    {
        return [
            ['from' => 0, 'to' => 50_000, 'rate' => 0],
            ['from' => 50_000, 'to' => 200_000, 'rate' => 12],
            ['from' => 200_000, 'to' => null, 'rate' => 25],
        ];
    }

    // ------------------------------------------------------- édition

    /** Le barème se modifie, et la nouvelle version est bien celle en base. */
    public function test_the_scale_can_be_edited(): void
    {
        $this->enregistrer($this->baremeValide())->assertHasNoErrors();

        $tranches = IncomeTaxBracket::orderBy('from_amount')->get();

        $this->assertCount(3, $tranches);
        $this->assertEquals(50_000, (float) $tranches[0]->to_amount);
        $this->assertEquals(12, (float) $tranches[1]->rate);
        $this->assertNull($tranches[2]->to_amount, 'La derniere tranche reste ouverte.');
    }

    /**
     * LE POINT CENTRAL : le calcul reprend automatiquement le nouveau barème.
     */
    public function test_the_calculation_picks_up_the_new_scale_immediately(): void
    {
        $service = app(PayrollCalculationService::class);

        // Barème semé : (96 400 − 60 000) × 10 % = 3 640
        $this->assertEquals(3_640, $service->calculer(100_000)['its']);

        $this->enregistrer($this->baremeValide());

        // Nouveau barème : (96 400 − 50 000) × 12 % = 5 568
        $this->assertEquals(5_568, app(PayrollCalculationService::class)->calculer(100_000)['its'],
            'Le calcul doit reprendre le nouveau bareme sans redeploiement.');
    }

    /** La simulation de l'écran utilise le service, pas une formule locale. */
    public function test_the_on_screen_simulation_uses_the_payroll_service(): void
    {
        $simulation = Livewire::test(BaremeIts::class)
            ->set('brutSimule', 100_000)
            ->instance()
            ->simulation;

        $this->assertEquals(3_640, $simulation['its']);
        $this->assertEquals(92_760, $simulation['net']);
        $this->assertEquals(21_400, $simulation['total_charges_patronales']);
    }

    // ------------------------------------------------------- verrouillage

    /**
     * LA RÈGLE DEMANDÉE : la première édition est ouverte, les suivantes sont
     * réservées à l'administrateur.
     */
    public function test_the_first_edit_is_open_then_locked_to_the_admin(): void
    {
        $this->assertFalse(CompanySetting::current()->payrollSettingsLocked());

        $this->enregistrer($this->baremeValide())->assertHasNoErrors();

        $this->assertTrue(CompanySetting::current()->fresh()->payrollSettingsLocked());

        // Le comptable ne peut plus y revenir.
        $this->enregistrer([
            ['from' => 0, 'to' => null, 'rate' => 5],
        ])->assertHasErrors(['tranches']);

        $this->assertCount(3, IncomeTaxBracket::all(), 'Le bareme arrete ne doit pas avoir bouge.');
    }

    /** L'administrateur, lui, peut revenir sur un barème arrêté. */
    public function test_an_admin_can_still_edit_a_locked_scale(): void
    {
        $this->enregistrer($this->baremeValide());

        $this->enregistrer([
            ['from' => 0, 'to' => 80_000, 'rate' => 0],
            ['from' => 80_000, 'to' => null, 'rate' => 20],
        ], $this->admin)->assertHasNoErrors();

        $this->assertCount(2, IncomeTaxBracket::all());
    }

    /** Qui a figé le paramétrage, et quand, reste tracé. */
    public function test_the_lock_records_who_and_when(): void
    {
        $this->enregistrer($this->baremeValide());

        $settings = CompanySetting::current()->fresh();

        $this->assertNotNull($settings->payroll_settings_edited_at);
        $this->assertEquals($this->comptable->id, $settings->payroll_settings_edited_by);
    }

    // --------------------------------------------- cohérence des tranches

    /**
     * ⚠️ UN TROU LAISSE UNE PORTION DE REVENU NON IMPOSÉE — sans lever
     * d'erreur au calcul.
     */
    public function test_a_gap_between_brackets_is_refused(): void
    {
        $this->enregistrer([
            ['from' => 0, 'to' => 50_000, 'rate' => 0],
            ['from' => 90_000, 'to' => null, 'rate' => 20],   // trou de 40 000
        ])->assertHasErrors(['tranches']);

        $this->assertCount(5, IncomeTaxBracket::all(), 'Le bareme seme reste intact.');
    }

    /** Un chevauchement taxerait deux fois la même portion. */
    public function test_an_overlap_is_refused(): void
    {
        $this->enregistrer([
            ['from' => 0, 'to' => 100_000, 'rate' => 0],
            ['from' => 50_000, 'to' => null, 'rate' => 20],
        ])->assertHasErrors(['tranches']);
    }

    /** Sans première tranche à zéro, les bas revenus ne seraient couverts par rien. */
    public function test_the_first_bracket_must_start_at_zero(): void
    {
        $this->enregistrer([
            ['from' => 30_000, 'to' => null, 'rate' => 10],
        ])->assertHasErrors(['tranches']);
    }

    /** Sans dernière tranche ouverte, les hauts revenus échapperaient à l'impôt. */
    public function test_the_last_bracket_must_be_open_ended(): void
    {
        $this->enregistrer([
            ['from' => 0, 'to' => 50_000, 'rate' => 0],
            ['from' => 50_000, 'to' => 200_000, 'rate' => 15],
        ])->assertHasErrors(['tranches']);
    }

    public function test_a_rate_outside_zero_to_hundred_is_refused(): void
    {
        $this->enregistrer([
            ['from' => 0, 'to' => null, 'rate' => 150],
        ])->assertHasErrors(['tranches']);
    }

    // ------------------------------------------- bulletins déjà réglés

    /**
     * ⚠️ UN BULLETIN DÉJÀ RÉGLÉ N'EST JAMAIS RECALCULÉ. Son écriture comptable
     * est passée, la trésorerie a bougé, le salarié a été payé : le recalculer
     * réécrirait l'histoire et ferait diverger le registre de paie du grand
     * livre — le défaut corrigé au ticket 14.33 sur les dépenses.
     */
    public function test_an_already_settled_payslip_is_never_recomputed(): void
    {
        $employe = Employee::create([
            'first_name' => 'Kossi', 'last_name' => 'ADJOVI',
            'base_salary' => 100_000, 'hire_date' => now()->subYear()->format('Y-m-d'),
            'status' => 'actif', 'is_active' => true,
        ]);

        $bulletin = \App\Models\Payslip::create([
            'employee_id' => $employe->id,
            'period_month' => now()->startOfMonth()->format('Y-m-d'),
            'gross_salary' => 100_000, 'absence_deduction' => 0,
            'cnss_deduction' => 3_600, 'its_deduction' => 3_640,
            'net_salary' => 92_760,
        ]);

        $this->enregistrer($this->baremeValide());

        $this->assertEquals(3_640, (float) $bulletin->fresh()->its_deduction,
            "Le bulletin regle conserve l'impot reellement retenu.");
        $this->assertEquals(92_760, (float) $bulletin->fresh()->net_salary);
    }
}
