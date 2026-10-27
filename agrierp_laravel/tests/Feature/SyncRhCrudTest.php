<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Employee;
use App\Models\Internship;
use App\Models\InternshipAbsence;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Tickets RH-1 / RH-2 — LE CRUD RH DU POSTE PASSE PAR LES ACTIONS DU WEB.
 *
 * Employés, stagiaires et absences de stagiaire se créent, se modifient et s'archivent au poste, hors ligne, et sont
 * rejoués ici par `SaisieEmployeAction` / `SaisieStagiaireAction` — les points de passage uniques de `RegistreEmployes`
 * et `RegistreStagiaires`. Mêmes règles, mêmes effets (audit, Corbeille), mêmes messages ; renvois acquittés sans
 * réécriture ; rôle exigé.
 */
class SyncRhCrudTest extends TestCase
{
    use RefreshDatabase;

    private User $rh;

    private const EMPLOYE = '77777777-7777-4777-8777-777777777777';

    private const STAGIAIRE = '66666666-6666-4666-8666-666666666666';

    private const ABSENCE = '88888888-8888-4888-8888-888888888888';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $this->rh = User::create([
            'name' => 'RH', 'username' => 'rh', 'email' => 'rh@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->rh->assignRole('admin');
    }

    private function pousser(array $corps, ?User $qui = null): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($qui ?? $this->rh, 'sanctum')->postJson('/api/sync/push', $corps);
    }

    /** @return array<string, mixed> */
    private function employe(array $remplacements = []): array
    {
        return array_merge([
            'id' => self::EMPLOYE, 'first_name' => 'Ange', 'last_name' => 'TOSSOU', 'position' => 'Ouvrier agricole',
            'hire_date' => '2026-10-01', 'base_salary' => 45000, 'status' => 'actif',
        ], $remplacements);
    }

    /** @return array<string, mixed> */
    private function stagiaire(array $remplacements = []): array
    {
        return array_merge([
            'id' => self::STAGIAIRE, 'first_name' => 'Félicité', 'last_name' => 'ADJOVI', 'school' => 'Lycée agricole de Sékou',
            'start_date' => '2026-02-01', 'end_date' => '2026-05-31', 'monthly_fee' => 25000, 'fee_paid' => false,
        ], $remplacements);
    }

    // ───────────── Employés ─────────────

    public function test_un_employe_cree_au_poste_existe_avec_sa_trace_et_son_identifiant(): void
    {
        $this->pousser(['employees' => [$this->employe()]])->assertOk()->assertJsonPath('employees.accepted.0', self::EMPLOYE);

        $e = Employee::findOrFail(self::EMPLOYE);
        $this->assertSame('TOSSOU', $e->last_name);
        $this->assertTrue($e->is_active);
        $this->assertEquals(45000, (float) $e->base_salary);
        $this->assertSame(1, AuditLog::where('action', 'employee.created')->count());
    }

    public function test_un_envoi_rejoue_identique_est_acquitte_sans_rien_ecrire(): void
    {
        $this->pousser(['employees' => [$this->employe()]])->assertOk();
        $this->pousser(['employees' => [$this->employe()]])->assertOk()->assertJsonPath('employees.accepted.0', self::EMPLOYE);

        $this->assertSame(1, AuditLog::where('action', 'employee.created')->count());
        $this->assertSame(0, AuditLog::where('action', 'employee.updated')->count());
    }

    public function test_une_modification_au_poste_est_rejouee_avec_sa_trace(): void
    {
        $this->pousser(['employees' => [$this->employe()]])->assertOk();
        $this->pousser(['employees' => [$this->employe(['base_salary' => 50000, 'status' => 'conge'])]])->assertOk();

        $e = Employee::findOrFail(self::EMPLOYE);
        $this->assertEquals(50000, (float) $e->base_salary);
        $this->assertSame('conge', $e->status);
        $this->assertSame(1, AuditLog::where('action', 'employee.updated')->count());
    }

    public function test_un_archivage_au_poste_archive_une_fois_avec_l_entite_pour_la_corbeille(): void
    {
        $this->pousser(['employees' => [$this->employe()]])->assertOk();
        $this->pousser(['employees' => [$this->employe(['is_active' => false])]])->assertOk();
        $this->pousser(['employees' => [$this->employe(['is_active' => false])]])->assertOk();

        $this->assertFalse(Employee::findOrFail(self::EMPLOYE)->is_active);
        $trace = AuditLog::where('action', 'employee.archived')->get();
        $this->assertCount(1, $trace);
        $this->assertSame(self::EMPLOYE, $trace->first()->entity_id);
    }

    public function test_un_employe_archive_ne_se_modifie_plus_motif_du_web(): void
    {
        $this->pousser(['employees' => [$this->employe()]])->assertOk();
        $this->pousser(['employees' => [$this->employe(['is_active' => false])]])->assertOk();

        $reponse = $this->pousser(['employees' => [$this->employe(['base_salary' => 99000])]])->assertOk();

        $this->assertSame([], $reponse->json('employees.accepted'));
        $this->assertStringContainsString(\App\Actions\SaisieEmployeAction::MESSAGE_ARCHIVE, $reponse->json('employees.rejected.0.reason'));
        $this->assertEquals(45000, (float) Employee::findOrFail(self::EMPLOYE)->base_salary);
    }

    public function test_un_employe_invalide_est_refuse_avec_un_motif_francais(): void
    {
        $reponse = $this->pousser(['employees' => [$this->employe(['last_name' => '', 'status' => 'parti'])]])->assertOk();

        $this->assertSame([], $reponse->json('employees.accepted'));
        $this->assertNull(Employee::find(self::EMPLOYE));
        $this->assertDoesNotMatchRegularExpression('/\b(required|invalid|must be)\b/i', $reponse->json('employees.rejected.0.reason'));
    }

    public function test_sans_le_role_rh_les_registres_sont_refuses(): void
    {
        $caisse = User::create([
            'name' => 'Caisse', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $caisse->assignRole('caissier');

        $reponse = $this->pousser([
            'employees' => [$this->employe()],
            'internships' => [$this->stagiaire()],
            'internship_absences' => [['id' => self::ABSENCE, 'internship_id' => self::STAGIAIRE, 'absence_date' => '2026-03-02']],
        ], $caisse)->assertOk();

        foreach (['employees', 'internships', 'internship_absences'] as $table) {
            $this->assertSame([], $reponse->json("$table.accepted"), $table);
            $this->assertStringContainsString('votre rôle ne permet pas', $reponse->json("$table.rejected.0.reason"), $table);
        }
        $this->assertSame(0, Employee::count() + Internship::count());
    }

    public function test_le_tirage_sert_les_employes_archives_avec_is_active(): void
    {
        $this->pousser(['employees' => [$this->employe(), $this->employe(['id' => '77777777-7777-4777-8777-777777777778', 'is_active' => false])]])->assertOk();

        $reponse = $this->actingAs($this->rh, 'sanctum')->getJson('/api/sync/pull')->assertOk();
        $servis = collect($reponse->json('employees'))->keyBy('id');

        $this->assertTrue($servis[self::EMPLOYE]['is_active']);
        $this->assertFalse($servis['77777777-7777-4777-8777-777777777778']['is_active']);
    }

    // ───────────── Stagiaires et absences ─────────────

    public function test_un_stagiaire_cree_puis_modifie_au_poste(): void
    {
        $this->pousser(['internships' => [$this->stagiaire()]])->assertOk()->assertJsonPath('internships.accepted.0', self::STAGIAIRE);
        $this->pousser(['internships' => [$this->stagiaire(['fee_paid' => true, 'end_date' => null])]])->assertOk();

        $s = Internship::findOrFail(self::STAGIAIRE);
        $this->assertTrue($s->fee_paid);
        $this->assertNull($s->end_date);
        $this->assertSame(1, AuditLog::where('action', 'internship.created')->count());
        $this->assertSame(1, AuditLog::where('action', 'internship.updated')->count());
    }

    public function test_une_fin_avant_le_debut_est_refusee(): void
    {
        $reponse = $this->pousser(['internships' => [$this->stagiaire(['end_date' => '2026-01-01'])]])->assertOk();

        $this->assertSame([], $reponse->json('internships.accepted'));
        $this->assertSame(0, Internship::count());
    }

    public function test_une_absence_notee_au_poste_dans_le_meme_envoi_que_son_stagiaire_puis_archivee(): void
    {
        $this->pousser([
            'internship_absences' => [['id' => self::ABSENCE, 'internship_id' => self::STAGIAIRE, 'absence_date' => '2026-03-02', 'reason' => 'Maladie']],
            'internships' => [$this->stagiaire()],
        ])->assertOk()->assertJsonPath('internship_absences.accepted.0', self::ABSENCE);

        $a = InternshipAbsence::findOrFail(self::ABSENCE);
        $this->assertSame('Maladie', $a->reason);
        $this->assertTrue($a->is_active);
        $this->assertSame(1, AuditLog::where('action', 'internship_absence.recorded')->count());

        // Renvoyée : rien de plus. Archivée : une fois, avec l'entité.
        $this->pousser(['internship_absences' => [['id' => self::ABSENCE, 'internship_id' => self::STAGIAIRE, 'absence_date' => '2026-03-02']]])->assertOk();
        $this->assertSame(1, AuditLog::where('action', 'internship_absence.recorded')->count());

        $this->pousser(['internship_absences' => [['id' => self::ABSENCE, 'internship_id' => self::STAGIAIRE, 'absence_date' => '2026-03-02', 'is_active' => false]]])->assertOk();
        $this->pousser(['internship_absences' => [['id' => self::ABSENCE, 'internship_id' => self::STAGIAIRE, 'absence_date' => '2026-03-02', 'is_active' => false]]])->assertOk();
        $this->assertFalse(InternshipAbsence::findOrFail(self::ABSENCE)->is_active);
        $this->assertSame(1, AuditLog::where('action', 'internship_absence.archived')->where('entity_id', self::ABSENCE)->count());

        // Le tirage la sert, archivée comprise.
        $servies = collect($this->actingAs($this->rh, 'sanctum')->getJson('/api/sync/pull')->assertOk()->json('internship_absences'));
        $this->assertFalse($servies->firstWhere('id', self::ABSENCE)['is_active']);
        $this->assertSame('2026-03-02', $servies->firstWhere('id', self::ABSENCE)['absence_date']);
    }

    public function test_une_absence_d_un_stagiaire_inconnu_est_refusee(): void
    {
        $reponse = $this->pousser(['internship_absences' => [['id' => self::ABSENCE, 'internship_id' => self::STAGIAIRE, 'absence_date' => '2026-03-02']]])->assertOk();

        $this->assertSame([], $reponse->json('internship_absences.accepted'));
        $this->assertSame(0, InternshipAbsence::count());
    }
}
