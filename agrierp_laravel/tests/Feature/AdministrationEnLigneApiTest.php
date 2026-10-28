<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\PersonalAccessToken;
use Tests\TestCase;

/**
 * Tickets PA-1, PA-5, PA-6, PA-8 — GESTES D'ADMINISTRATION EN LIGNE depuis le poste : mêmes services, mêmes droits que le web.
 */
class AdministrationEnLigneApiTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $simple;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['manage-users', 'manage-parametres'] as $p) {
            Permission::findOrCreate($p, 'web');
        }
        Role::findOrCreate('admin', 'web')->givePermissionTo(['manage-users', 'manage-parametres']);
        Role::findOrCreate('simple', 'web');
        $this->admin = $this->utilisateur('admin');
        $this->simple = $this->utilisateur('simple');
    }

    private function utilisateur(string $role): User
    {
        $u = User::create(['name' => ucfirst($role), 'username' => $role, 'email' => $role.'@ferme.test', 'password' => bcrypt('x'), 'is_active' => true]);
        $u->assignRole($role);

        return $u;
    }

    public function test_chaque_geste_exige_son_droit(): void
    {
        $this->actingAs($this->simple, 'sanctum');

        $this->postJson('/api/parametres/sessions/vider')->assertForbidden();
        $this->getJson('/api/parametres/postes')->assertForbidden();
        $this->postJson('/api/parametres/postes/revoquer', ['poste' => 'x'])->assertForbidden();
        $this->getJson('/api/parametres/sauvegardes')->assertForbidden();
        $this->postJson('/api/parametres/sauvegardes/generer')->assertForbidden();
    }

    public function test_vider_les_sessions_conserve_le_jeton_de_l_auteur_et_deconnecte_les_autres_postes(): void
    {
        $moi = $this->admin->createToken('bureau');
        $autre = $this->simple->createToken('comptoir');

        $this->withHeader('Authorization', 'Bearer '.$moi->plainTextToken)
            ->postJson('/api/parametres/sessions/vider')->assertOk()->assertJsonPath('jetons', 1);

        $this->assertNotNull(PersonalAccessToken::find($moi->accessToken->getKey()));
        $this->assertNull(PersonalAccessToken::find($autre->accessToken->getKey()));
        $this->assertTrue(AuditLog::where('action', 'sessions.videes')->exists());
    }

    public function test_les_postes_se_listent_se_sollicitent_et_se_revoquent_seulement_s_ils_existent(): void
    {
        $this->simple->createToken('comptoir-1');
        $this->actingAs($this->admin, 'sanctum');

        $this->assertSame(['comptoir-1'], collect($this->getJson('/api/parametres/postes')->assertOk()->json('postes'))->pluck('poste')->all());
        $this->postJson('/api/parametres/postes/demander', ['poste' => 'inconnu'])->assertStatus(422);
        $this->postJson('/api/parametres/postes/demander', ['poste' => 'comptoir-1'])->assertOk();
        $this->postJson('/api/parametres/postes/revoquer', ['poste' => 'inconnu'])->assertStatus(422);
        $this->postJson('/api/parametres/postes/revoquer', ['poste' => 'comptoir-1'])->assertOk();
        $this->assertSame(0, PersonalAccessToken::where('name', 'comptoir-1')->count());
        $this->assertTrue(AuditLog::where('action', 'sync.appairage_revoque')->exists());
    }

    public function test_les_sauvegardes_se_listent_se_generent_par_module_et_refusent_un_module_inconnu(): void
    {
        $this->actingAs($this->admin, 'sanctum');

        $this->getJson('/api/parametres/sauvegardes')->assertOk()->assertJsonStructure(['fichiers', 'modules']);
        $this->postJson('/api/parametres/sauvegardes/generer', ['module' => 'inconnu'])->assertStatus(422);
        $this->postJson('/api/parametres/sauvegardes/generer', ['module' => 'ventes'])->assertOk()->assertJsonPath('type', 'success');
        $this->assertNotEmpty($this->getJson('/api/parametres/sauvegardes')->json('fichiers'));
        $this->getJson('/api/parametres/sauvegardes/telecharger/introuvable.sql')->assertNotFound();
        $this->postJson('/api/parametres/sauvegardes/importer', [])->assertStatus(422);
    }
}
