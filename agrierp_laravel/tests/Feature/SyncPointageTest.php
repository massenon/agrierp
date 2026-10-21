<?php

namespace Tests\Feature;

use App\Models\AttendanceRecord;
use App\Models\Employee;
use App\Models\Internship;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.81 (Sprint 14) — LE POINTAGE ENTRE DANS LE CONTRAT DE SYNCHRO.
 *
 * ⚠️⚠️ LE POINTAGE EST L'ACTE DE TERRAIN PAR EXCELLENCE : il se fait à 7 h à la
 * ferme, là où le réseau n'est pas. Sans les employés au poste, il n'y a
 * personne à pointer ; sans les pointages déjà saisis, le chef d'équipe
 * repointe quelqu'un que le web connaît déjà.
 *
 * ⚠️⚠️ L'IDENTITÉ D'UN POINTAGE N'EST PAS SON UUID, C'EST LE COUPLE
 * (EMPLOYÉ, JOUR). La table porte `unique(employee_id, attendance_date)` depuis
 * le ticket 8.1 : un simple `insert` échouerait dès que le web a déjà pointé la
 * même personne le même matin — et le poste rejouerait indéfiniment un envoi
 * rejeté.
 */
class SyncPointageTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    private Employee $employe;

    protected function setUp(): void
    {
        parent::setUp();

        $this->utilisateur = User::create([
            'name' => "Chef d'équipe", 'username' => 'rh',
            'email' => 'rh@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);

        // Ticket S1 : l'envoi du poste exige désormais le rôle qui écrit chaque table.

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $this->utilisateur->assignRole('admin');

        $this->employe = Employee::create([
            'first_name' => 'Kossi', 'last_name' => 'AGBODJI',
            'position' => "Chef d'élevage", 'base_salary' => 120000,
            'hire_date' => '2025-03-01', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    /** @return array<string, mixed> */
    private function pointage(array $remplacements = []): array
    {
        return array_merge([
            'id' => '55555555-5555-4555-8555-555555555555',
            'employee_id' => $this->employe->id,
            'attendance_date' => now()->toDateString(),
            'check_in' => '07:00',
            'check_out' => null,
            'status' => 'present',
        ], $remplacements);
    }

    private function pousser(array $pointages): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($this->utilisateur, 'sanctum')
            ->postJson('/api/sync/push', ['attendance_records' => $pointages]);
    }

    private function tirer(): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($this->utilisateur, 'sanctum')->getJson('/api/sync/pull');
    }

    public function test_a_pushed_attendance_reaches_the_server(): void
    {
        $this->pousser([$this->pointage()])
            ->assertOk()
            ->assertJsonPath('attendance_records.accepted.0', '55555555-5555-4555-8555-555555555555');

        $ligne = AttendanceRecord::find('55555555-5555-4555-8555-555555555555');

        $this->assertNotNull($ligne, "L'UUID du poste doit être conservé : `id` "
            ."n'est pas remplissable, et `create(['id' => …])` l'ignorerait en silence.");
        $this->assertSame('present', $ligne->status);
    }

    /**
     * ⚠️⚠️ LE CAS QUI CASSE UN `insert` NAÏF : le web a déjà pointé la même
     * personne le même matin. Le pointage du poste doit COMPLÉTER la ligne, pas
     * en créer une seconde — la contrainte d'unicité la refuserait, et le poste
     * rejouerait le même envoi indéfiniment.
     */
    public function test_an_attendance_already_recorded_on_the_web_is_completed_not_duplicated(): void
    {
        $existant = AttendanceRecord::create([
            'employee_id' => $this->employe->id,
            'attendance_date' => now()->toDateString(),
            'check_in' => '07:05',
            'status' => 'present',
            'is_active' => true,
        ]);

        $this->pousser([$this->pointage(['status' => 'retard', 'check_in' => '08:30'])])
            ->assertOk()
            ->assertJsonCount(1, 'attendance_records.accepted');

        $this->assertSame(1, AttendanceRecord::count());
        $this->assertSame('retard', $existant->fresh()->status);
        // ⚠️ MySQL rend « 08:30:00 », SQLite « 08:30 » : le test compare
        // l'HEURE, pas sa mise en forme par le pilote.
        $this->assertStringStartsWith('08:30', $existant->fresh()->check_in);
    }

    /** ⚠️ Rejouer le même envoi ne crée pas de doublon. */
    public function test_a_replayed_attendance_changes_nothing(): void
    {
        $this->pousser([$this->pointage()])->assertOk();
        $this->pousser([$this->pointage()])->assertOk();

        $this->assertSame(1, AttendanceRecord::count());
    }

    /** Un employé inconnu du serveur est refusé — jamais inventé. */
    public function test_an_unknown_employee_is_refused(): void
    {
        $reponse = $this->pousser([
            $this->pointage(['employee_id' => '00000000-0000-4000-8000-000000000000']),
        ])->assertOk();

        $reponse->assertJsonCount(1, 'attendance_records.rejected');
        $this->assertSame(0, AttendanceRecord::count());
    }

    /** Un pointage daté de demain est refusé : on ne pointe pas d'avance. */
    public function test_an_attendance_dated_in_the_future_is_refused(): void
    {
        $reponse = $this->pousser([
            $this->pointage(['attendance_date' => now()->addDay()->toDateString()]),
        ])->assertOk();

        $reponse->assertJsonCount(1, 'attendance_records.rejected');
    }

    /**
     * ⚠️ LE SERVEUR SERT « 07:05:00 » : la validation de l'envoi doit accepter
     * les deux formes, sinon un pointage renvoyé tel quel serait rejeté.
     */
    public function test_both_time_formats_are_accepted(): void
    {
        $this->pousser([$this->pointage(['check_in' => '07:05:00'])])
            ->assertOk()
            ->assertJsonCount(1, 'attendance_records.accepted');
    }

    /** 🔴→✅ Employés, stagiaires et pointages descendent au poste. */
    public function test_the_hr_referentials_reach_the_device(): void
    {
        Internship::create([
            'first_name' => 'Ange', 'last_name' => 'TOSSOU',
            'school' => 'Lycée Agricole de Sékou',
            'start_date' => now()->subMonths(2)->toDateString(),
            'end_date' => now()->toDateString(),
            'monthly_fee' => 25000, 'fee_paid' => true,
        ]);
        $this->pousser([$this->pointage()])->assertOk();

        $reponse = $this->tirer()->assertOk();

        $reponse->assertJsonCount(1, 'employees')
            ->assertJsonPath('employees.0.last_name', 'AGBODJI')
            ->assertJsonCount(1, 'internships')
            ->assertJsonPath('internships.0.school', 'Lycée Agricole de Sékou')
            ->assertJsonCount(1, 'attendance_records');
    }

    /**
     * ⚠️⚠️ LE JOUR SE SERT EN 'Y-m-d', JAMAIS EN INSTANT. Eloquent sérialise une
     * colonne `date` en « 2026-08-16T23:00:00Z » : le 17 août local devient le
     * 16 à 23 h UTC, et un poste qui lit l'instant sans le ramener à l'heure
     * locale pointe la veille. Le même piège a déjà coûté une échéance de
     * créance (ticket 14.75).
     */
    public function test_the_attendance_day_is_served_as_a_plain_date(): void
    {
        $this->pousser([$this->pointage()])->assertOk();

        $this->tirer()
            ->assertOk()
            ->assertJsonPath('attendance_records.0.attendance_date', now()->toDateString());
    }

    /** ⚠️ Employés et stagiaires sont des référentiels : tout envoi est ignoré ET compté. */
    public function test_the_registers_cannot_be_written_from_the_device(): void
    {
        $reponse = $this->actingAs($this->utilisateur, 'sanctum')->postJson('/api/sync/push', [
            'employees' => [['id' => $this->employe->id, 'last_name' => 'FALSIFIÉ']],
            'internships' => [['id' => '66666666-6666-4666-8666-666666666666']],
        ]);

        $reponse->assertOk();
        $this->assertGreaterThanOrEqual(2, $reponse->json('referentiels_ignored'));
        $this->assertSame('AGBODJI', $this->employe->fresh()->last_name);
        $this->assertSame(0, Internship::count());
    }
}
