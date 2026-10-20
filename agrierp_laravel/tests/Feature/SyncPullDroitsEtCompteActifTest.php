<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Employee;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\PersonalAccessToken;
use Tests\TestCase;

/**
 * Ticket S3 — CE QUE LE TIRAGE SERT, ET À QUI.
 *
 * 🔴 Avant ce ticket : tout compte connecté recevait les salaires et le journal d'audit ; un compte désactivé
 * sur le web continuait de synchroniser avec son jeton ; les jetons n'expiraient jamais.
 */
class SyncPullDroitsEtCompteActifTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        Employee::create([
            'first_name' => 'Koffi', 'last_name' => 'Adjovi', 'position' => 'Ouvrier',
            'base_salary' => 85000, 'hire_date' => '2026-01-05', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    private function compte(string $role, bool $actif = true): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role,
            'email' => $role.'@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => $actif,
        ]);
        $u->assignRole($role);

        return $u;
    }

    public function test_le_salaire_ne_descend_pas_au_poste_du_caissier(): void
    {
        $reponse = $this->actingAs($this->compte('caissier'), 'sanctum')->getJson('/api/sync/pull');

        $reponse->assertOk();
        $reponse->assertJsonPath('employees.0.first_name', 'Koffi');
        $reponse->assertJsonPath('employees.0.base_salary', null);
    }

    public function test_le_salaire_descend_a_l_administrateur(): void
    {
        $reponse = $this->actingAs($this->compte('admin'), 'sanctum')->getJson('/api/sync/pull');

        $this->assertEquals(85000, (float) $reponse->json('employees.0.base_salary'));
    }

    public function test_le_journal_d_audit_est_reserve_a_l_administrateur(): void
    {
        AuditLog::record('user.archived', 'parametres');

        $this->actingAs($this->compte('animalier'), 'sanctum')->getJson('/api/sync/pull')
            ->assertJsonPath('audit_logs', []);

        $this->assertNotEmpty(
            $this->actingAs($this->compte('admin'), 'sanctum')->getJson('/api/sync/pull')->json('audit_logs'),
        );
    }

    public function test_un_compte_desactive_ne_synchronise_plus_et_son_jeton_est_revoque(): void
    {
        $compte = $this->compte('caissier');
        $jeton = $compte->createToken('poste-test')->plainTextToken;

        $compte->update(['is_active' => false]);

        $this->withHeader('Authorization', 'Bearer '.$jeton)->getJson('/api/sync/pull')
            ->assertStatus(403)
            ->assertJsonPath('message', "Compte désactivé : contactez l'administrateur de la ferme.");

        $this->assertSame(0, PersonalAccessToken::count());
    }

    public function test_archiver_un_utilisateur_revoque_les_jetons_de_ses_postes(): void
    {
        $admin = $this->compte('admin');
        $caissier = $this->compte('caissier');
        $caissier->createToken('poste-comptoir');

        \Livewire\Livewire::actingAs($admin)
            ->test(\App\Livewire\Parametres\GestionUtilisateurs::class)
            ->call('archiveUser', $caissier->id);

        $this->assertFalse((bool) $caissier->fresh()->is_active);
        $this->assertSame(0, $caissier->tokens()->count());
    }

    public function test_un_jeton_expire_apres_quatre_vingt_dix_jours(): void
    {
        $this->assertSame(60 * 24 * 90, config('sanctum.expiration'));

        $compte = $this->compte('caissier');
        $jeton = $compte->createToken('poste-ancien');
        $jeton->accessToken->forceFill(['created_at' => now()->subDays(91)])->save();

        $this->withHeader('Authorization', 'Bearer '.$jeton->plainTextToken)->getJson('/api/sync/pull')
            ->assertStatus(401);
    }
}
