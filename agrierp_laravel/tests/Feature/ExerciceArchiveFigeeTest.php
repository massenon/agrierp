<?php

namespace Tests\Feature;

use App\Livewire\Parametres\ReinitialisationDonnees;
use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\FiscalYear;
use App\Models\FiscalYearArchive;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket EX9 — Archive figée de l'exercice + garde de réinitialisation + journal d'audit.
 */
class ExerciceArchiveFigeeTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->admin = User::create([
            'name' => 'Directeur', 'username' => 'admin',
            'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('LogiAgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('admin');
    }

    private function exerciceCloture(): FiscalYear
    {
        return FiscalYear::create([
            'year' => 2023,
            'start_date' => '2023-01-01',
            'end_date' => '2023-12-31',
            'status' => 'cloture',
            'closed_at' => now()->subDay(),
            'closed_by' => $this->admin->id,
        ]);
    }

    // ─────────────────────────────────────────────────────────────
    // 1. Une archive est créée à la clôture d'un exercice
    // ─────────────────────────────────────────────────────────────

    public function test_une_archive_est_creee_a_la_cloture(): void
    {
        $year = FiscalYear::create([
            'year' => 2022,
            'start_date' => '2022-01-01',
            'end_date' => '2022-12-31',
            'status' => 'cloture',
            'closed_at' => now()->subDay(),
            'closed_by' => $this->admin->id,
            'step1_confirmed_at' => now()->subDays(2),
        ]);

        FiscalYearArchive::creerDepuisExercice($year);

        $this->assertDatabaseHas('fiscal_year_archives', [
            'fiscal_year_id' => $year->id,
        ]);

        $archive = FiscalYearArchive::where('fiscal_year_id', $year->id)->first();
        $this->assertNotNull($archive);
        $this->assertIsArray($archive->bilan);
        $this->assertIsArray($archive->compte_resultat);
        $this->assertIsArray($archive->balance);
        $this->assertNotNull($archive->cloture_at);
    }

    // ─────────────────────────────────────────────────────────────
    // 2. La réinitialisation est refusée si un exercice est clos
    // ─────────────────────────────────────────────────────────────

    public function test_reinitialisation_refusee_si_exercice_clos(): void
    {
        $this->exerciceCloture();

        CompanySetting::create(['company_name' => 'Ferme', 'demo_mode_enabled' => true]);

        Livewire::actingAs($this->admin)
            ->test(ReinitialisationDonnees::class)
            ->set('confirmation', 'REINITIALISER')
            ->call('reinitialiser')
            ->assertDispatched('toast', fn ($name, $params) => str_contains(
                $params['message'] ?? '',
                'exercice a été clôturé'
            ));
    }

    // ─────────────────────────────────────────────────────────────
    // 3. La réinitialisation passe quand aucun exercice n'est clos
    //    (garde EX9 non déclenchée)
    // ─────────────────────────────────────────────────────────────

    public function test_reinitialisation_passe_sans_exercice_clos(): void
    {
        // Aucun exercice clos — mais le mode démo doit être actif pour franchir le verrou 1.
        CompanySetting::create(['company_name' => 'Ferme', 'demo_mode_enabled' => true]);

        // Pas d'exercice → la garde EX9 ne se déclenche pas, et le mode démo est actif.
        Livewire::actingAs($this->admin)
            ->test(ReinitialisationDonnees::class)
            ->set('confirmation', 'REINITIALISER')
            ->call('reinitialiser')
            ->assertDispatched('toast', fn ($name, $params) => ($params['type'] ?? '') === 'success');
    }

    // ─────────────────────────────────────────────────────────────
    // 4. Le refus de réinitialisation est journalisé
    // ─────────────────────────────────────────────────────────────

    public function test_refus_reinitialisation_est_journalise(): void
    {
        $this->exerciceCloture();
        CompanySetting::create(['company_name' => 'Ferme', 'demo_mode_enabled' => true]);

        Livewire::actingAs($this->admin)
            ->test(ReinitialisationDonnees::class)
            ->set('confirmation', 'REINITIALISER')
            ->call('reinitialiser');

        $this->assertDatabaseHas('audit_logs', [
            'action' => 'reinitialisation.refusee_exercice_clos',
            'module' => 'parametres',
        ]);
    }
}
