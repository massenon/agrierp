<?php

namespace Tests\Feature;

use App\Livewire\Parametres\GestionUtilisateurs;
use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\User;
use App\Services\ReinitialisationDonneesService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.54 — VIDER LES SESSIONS : sessions web et jetons des postes, en gardant la session de celui qui agit.
 */
class ViderSessionsTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->admin = $this->compte('admin');
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    private function sessionsEtJetons(): void
    {
        foreach (['sess-autre-1', 'sess-autre-2'] as $id) {
            DB::table('sessions')->insert(['id' => $id, 'payload' => '', 'last_activity' => time()]);
        }
        $this->compte('caissier')->createToken('poste-caisse');
        $this->compte('animalier')->createToken('poste-elevage');
    }

    public function test_le_bouton_vide_tout_sauf_la_session_en_cours(): void
    {
        $this->sessionsEtJetons();
        $this->actingAs($this->admin);
        $courante = session()->getId();
        DB::table('sessions')->insert(['id' => $courante, 'payload' => '', 'last_activity' => time()]);

        Livewire::test(GestionUtilisateurs::class)->call('viderSessions')
            ->assertDispatched('toast', type: 'success');

        $this->assertSame([$courante], DB::table('sessions')->pluck('id')->all());
        $this->assertSame(0, DB::table('personal_access_tokens')->count());
        $this->assertSame(1, AuditLog::where('action', 'sessions.videes')->count());
    }

    public function test_un_non_administrateur_ne_peut_pas_vider_les_sessions(): void
    {
        $this->sessionsEtJetons();
        $this->actingAs($this->compte('comptable'));

        Livewire::test(GestionUtilisateurs::class)->call('viderSessions')->assertForbidden();

        $this->assertSame(2, DB::table('personal_access_tokens')->count());
    }

    public function test_la_commande_vide_toutes_les_sessions(): void
    {
        $this->sessionsEtJetons();

        $this->artisan('agrierp:vider-sessions', ['--force' => true])
            ->expectsOutputToContain('2 session(s) web supprimée(s), 2 jeton(s) de poste révoqué(s)')
            ->assertSuccessful();

        $this->assertSame(0, DB::table('sessions')->count());
    }

    public function test_un_poste_dont_le_jeton_est_revoque_doit_se_reconnecter(): void
    {
        $jeton = $this->compte('caissier')->createToken('poste')->plainTextToken;
        $this->withToken($jeton)->getJson('/api/sync/pull')->assertOk();

        $this->artisan('agrierp:vider-sessions', ['--force' => true]);
        $this->app['auth']->forgetGuards();

        $this->withToken($jeton)->getJson('/api/sync/pull')->assertUnauthorized();
    }

    public function test_la_reinitialisation_vide_les_sessions_et_les_jetons(): void
    {
        CompanySetting::create(['company_name' => 'Ferme']);
        $this->sessionsEtJetons();

        app(ReinitialisationDonneesService::class)->executer();

        $this->assertSame(0, DB::table('personal_access_tokens')->count());
        $this->assertSame(0, DB::table('sessions')->count());
    }
}
