<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * Ticket 15.9 — `POST /api/auth/password` : le poste Flutter change enfin le
 * mot de passe de son utilisateur. Règle tranchée par le commanditaire :
 * 8 caractères, une majuscule, un chiffre.
 */
class ApiChangementMotDePasseTest extends TestCase
{
    use RefreshDatabase;

    private const ANCIEN = 'AgriERP@2026';

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        Role::findOrCreate('caissier', 'web');
        $this->user = User::create([
            'name' => 'Caissier Ferme',
            'username' => 'caisse',
            'email' => 'caisse@fermeolouwachegoun.com',
            'password' => bcrypt(self::ANCIEN),
            'is_active' => true,
        ]);
        $this->user->assignRole('caissier');
    }

    private function jeton(): string
    {
        return $this->postJson('/api/auth/login', [
            'identifiant' => 'caisse',
            'password' => self::ANCIEN,
            'device_name' => 'poste-01',
        ])->json('token');
    }

    private function changer(array $corps, ?string $jeton = null)
    {
        return $this->withHeader('Authorization', 'Bearer '.($jeton ?? $this->jeton()))
            ->postJson('/api/auth/password', array_merge([
                'current_password' => self::ANCIEN,
                'new_password' => 'Ferme2026',
                'new_password_confirmation' => 'Ferme2026',
            ], $corps));
    }

    public function test_un_changement_valide_remplace_le_mot_de_passe_et_se_journalise(): void
    {
        $this->changer([])->assertOk();

        $this->assertTrue(Hash::check('Ferme2026', $this->user->fresh()->password));
        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $this->user->id,
            'action' => 'password.updated',
        ]);
    }

    public function test_l_ancien_mot_de_passe_est_verifie_contre_le_hachage_reel(): void
    {
        $this->changer(['current_password' => 'FauxMotDePasse1'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('current_password');

        $this->assertTrue(Hash::check(self::ANCIEN, $this->user->fresh()->password));
    }

    #[\PHPUnit\Framework\Attributes\DataProvider('motsDePasseRefuses')]
    public function test_la_politique_huit_caracteres_une_majuscule_un_chiffre(string $mdp): void
    {
        $this->changer(['new_password' => $mdp, 'new_password_confirmation' => $mdp])
            ->assertStatus(422)
            ->assertJsonValidationErrors('new_password');

        $this->assertTrue(Hash::check(self::ANCIEN, $this->user->fresh()->password));
    }

    public static function motsDePasseRefuses(): array
    {
        return [
            'sept caractères' => ['Ferme20'],
            'sans majuscule' => ['ferme2026'],
            'sans chiffre' => ['FermeEcole'],
        ];
    }

    public function test_huit_caracteres_avec_majuscule_et_chiffre_sans_symbole_passent(): void
    {
        // ⚠️ Aucun symbole exigé : c'est la règle du commanditaire, pas celle du
        // ticket 14.65 (réinitialisation).
        $this->changer(['new_password' => 'Abcdefg1', 'new_password_confirmation' => 'Abcdefg1'])
            ->assertOk();
    }

    public function test_une_confirmation_differente_est_refusee(): void
    {
        $this->changer(['new_password_confirmation' => 'Ferme2027'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('new_password_confirmation');
    }

    public function test_la_route_est_fermee_sans_jeton(): void
    {
        $this->postJson('/api/auth/password', [])->assertStatus(401);
    }

    public function test_le_jeton_du_poste_reste_valide_apres_le_changement(): void
    {
        $jeton = $this->jeton();
        $this->changer([], $jeton)->assertOk();

        // Hors ligne, un poste ne doit pas être éjecté (voir le docblock).
        $this->withHeader('Authorization', 'Bearer '.$jeton)
            ->getJson('/api/auth/me')->assertOk();
    }
}
