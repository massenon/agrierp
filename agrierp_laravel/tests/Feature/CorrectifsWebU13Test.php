<?php

namespace Tests\Feature;

use App\Livewire\Elevage\SuiviReproduction;
use App\Livewire\Rapports\RecettesDepenses;
use App\Models\Employee;
use App\Models\LivestockLot;
use App\Models\LivestockReproductionEvent;
use App\Models\LivestockSpecies;
use App\Models\Payslip;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;
use App\Models\Permission;
use App\Models\Role;
use Tests\TestCase;

/**
 * Ticket U13 — deux défauts du WEB relevés par U12b (le poste, lui, faisait déjà juste) :
 *  1. « Échecs (mois) » du suivi de reproduction : `whereMonth` seul comptait les échecs du même mois des années
 *     passées (octobre 2025 dans « octobre 2026 ») ;
 *  2. libellé « Paie — … » de « Recettes et Dépenses » : `.` liant plus fort que `??` en PHP, le repli « Employé »
 *     ne s'appliquait jamais — un bulletin sans employé sortait « Paie —   ».
 */
class CorrectifsWebU13Test extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-19 10:00:00');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function connecter(array $permissions): void
    {
        foreach ($permissions as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('role-u13', 'web');
        $role->givePermissionTo($permissions);
        $u = User::create(['name' => 'Compte U13', 'email' => 'u13@olouwachegoun.bj', 'password' => bcrypt('AgriERP@2026')]);
        $u->assignRole($role);
        $this->actingAs($u);
    }

    public function test_echecs_du_mois_ne_compte_que_l_annee_courante(): void
    {
        $this->connecter(['view-elevage', 'manage-elevage']);
        $lapins = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);
        $lot = LivestockLot::create([
            'code' => 'LAP-R', 'species_id' => $lapins->id, 'stage' => 'reproduction', 'initial_quantity' => 20,
            'current_quantity' => 20, 'created_date' => '2025-01-01', 'status' => 'actif', 'is_active' => true,
        ]);

        // Échecs constatés (date de mise à jour) : octobre 2026 ×2, octobre 2025, octobre 2024, septembre 2026.
        foreach (['2026-10-03 08:00:00', '2026-10-18 17:00:00', '2025-10-10 09:00:00', '2024-10-02 09:00:00', '2026-09-28 09:00:00'] as $k => $quand) {
            $e = LivestockReproductionEvent::create([
                'lot_id' => $lot->id, 'mother_ref' => 'R'.$k, 'saillie_date' => substr($quand, 0, 10), 'status' => 'echec',
            ]);
            DB::table('livestock_reproduction_events')->where('id', $e->id)->update(['updated_at' => $quand]);
        }

        $kpis = Livewire::test(SuiviReproduction::class)->instance()->kpis;

        $this->assertSame(2, $kpis['echecs'], 'octobre 2026 seulement — ni octobre 2025, ni octobre 2024');
    }

    public function test_libelle_paie_nom_prenom_ou_employe_sans_employe(): void
    {
        $this->connecter(['view-rapports']);
        $employe = Employee::create(['first_name' => 'Codjo', 'last_name' => 'HOUNKPÈ', 'is_active' => true]);
        $avec = Payslip::create(['employee_id' => $employe->id, 'period_month' => '2026-10-01', 'gross_salary' => 100000, 'net_salary' => 96400]);

        // Un bulletin dont l'employé n'existe plus (clé étrangère contournée, comme une base restaurée partiellement) :
        // contrôle différé à la validation de la transaction du test, qui est annulée.
        DB::statement('PRAGMA defer_foreign_keys = ON');
        $sans = Payslip::create(['employee_id' => '99999999-9999-4999-8999-999999999999', 'period_month' => '2026-10-01', 'gross_salary' => 50000, 'net_salary' => 48200]);

        $this->assertSame('Paie — HOUNKPÈ Codjo', RecettesDepenses::libellePaie($avec->fresh()));
        $this->assertSame('Paie — Employé', RecettesDepenses::libellePaie($sans->fresh()));

        // Et à l'écran du rapport.
        $libelles = Livewire::test(RecettesDepenses::class, ['startDate' => '2026-10-01', 'endDate' => '2026-10-31'])
            ->instance()->depenses->pluck('label')->all();
        $this->assertEqualsCanonicalizing(['Paie — HOUNKPÈ Codjo', 'Paie — Employé'], $libelles);
    }
}
