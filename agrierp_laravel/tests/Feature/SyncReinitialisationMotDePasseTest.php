<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * Ticket MDP-1 — la réinitialisation faite AU POSTE (hors ligne, rejouée à l'envoi) passe par le même point de passage
 * que le web : `SaisieUtilisateurAction::reinitialiserMotDePasse`, clé d'envoi `users`, drapeau `reset_password`.
 */
class SyncReinitialisationMotDePasseTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $cible;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->admin = User::create(['name' => 'Directeur', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $this->admin->assignRole('admin');
        $this->cible = User::create(['name' => 'Afi', 'username' => 'afi', 'email' => 'afi@fermeolouwachegoun.com', 'password' => bcrypt('Ancien#2026'), 'is_active' => true]);
        $this->cible->assignRole('caissier');
    }

    private function ligne(User $u, array $plus = []): array
    {
        return array_merge([
            'id' => $u->id, 'name' => $u->name, 'username' => $u->username, 'email' => $u->email,
            'role' => $u->roles->first()->name, 'is_active' => true,
        ], $plus);
    }

    private function pousser(array $lignes, ?User $qui = null)
    {
        return $this->actingAs($qui ?? $this->admin, 'sanctum')->postJson('/api/sync/push', ['users' => $lignes]);
    }

    public function test_la_reinitialisation_du_poste_a_les_memes_effets_que_le_web(): void
    {
        $this->cible->createToken('poste-caisse');

        $this->pousser([$this->ligne($this->cible, ['password' => 'Temp#Ferme2026', 'reset_password' => true])])
            ->assertOk()->assertJsonPath('users.accepted.0', $this->cible->id);

        $u = $this->cible->fresh();
        $this->assertTrue($u->must_change_password);
        $this->assertTrue(Hash::check('Temp#Ferme2026', $u->password));
        $this->assertSame(0, $u->tokens()->count());
        $trace = AuditLog::where('action', 'user.password_reset')->first();
        $this->assertSame($this->admin->id, $trace->user_id);
        $this->assertSame($this->cible->id, $trace->entity_id);
        $this->assertStringNotContainsString('Temp#Ferme2026', json_encode(AuditLog::all()->toArray()));
    }

    public function test_un_renvoi_apres_reponse_perdue_est_acquitte_sans_nouvelle_trace(): void
    {
        $envoi = [$this->ligne($this->cible, ['password' => 'Temp#Ferme2026', 'reset_password' => true])];
        $this->pousser($envoi)->assertOk();
        $this->pousser($envoi)->assertOk()->assertJsonPath('users.accepted.0', $this->cible->id);

        $this->assertSame(1, AuditLog::where('action', 'user.password_reset')->count());
    }

    public function test_le_propre_compte_de_l_auteur_est_refuse_avec_le_motif_du_web(): void
    {
        $reponse = $this->pousser([$this->ligne($this->admin, ['password' => 'Temp#Ferme2026', 'reset_password' => true])])->assertOk();

        $this->assertSame([], $reponse->json('users.accepted'));
        $this->assertStringContainsString('Vous ne pouvez pas réinitialiser votre propre mot de passe', $reponse->json('users.rejected.0.reason'));
        $this->assertFalse($this->admin->fresh()->must_change_password);
        $this->assertTrue(Hash::check('AgriERP@2026', $this->admin->fresh()->password));
    }

    public function test_le_temporaire_est_obligatoire_et_suit_la_politique(): void
    {
        foreach ([null, '12345678'] as $faible) {
            $reponse = $this->pousser([$this->ligne($this->cible, ['password' => $faible, 'reset_password' => true])])->assertOk();
            $this->assertSame([], $reponse->json('users.accepted'));
            $this->assertStringContainsString('mot de passe', $reponse->json('users.rejected.0.reason'));
        }
        $this->assertFalse($this->cible->fresh()->must_change_password);
    }

    public function test_sans_manage_users_la_reinitialisation_est_refusee(): void
    {
        $caissier = User::create(['name' => 'Caisse', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $caissier->assignRole('caissier');

        $reponse = $this->pousser([$this->ligne($this->cible, ['password' => 'Temp#Ferme2026', 'reset_password' => true])], $caissier)->assertOk();

        $this->assertSame([], $reponse->json('users.accepted'));
        $this->assertFalse($this->cible->fresh()->must_change_password);
    }

    public function test_une_modification_ordinaire_ne_pose_jamais_le_drapeau(): void
    {
        $this->pousser([$this->ligne($this->cible, ['name' => 'Afi D.', 'password' => 'Autre#Mdp2026'])])->assertOk();

        $this->assertFalse($this->cible->fresh()->must_change_password);
    }
}
