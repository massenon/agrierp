<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * Ticket UT-1 — LES COMPTES UTILISATEURS S'ÉCRIVENT AU POSTE (demande du client du 27/10/2026 : « le poste ne crée pas
 * les utilisateurs or normalement il le devrait »).
 *
 * Le poste envoie `users` ; le serveur rejoue par `SaisieUtilisateurAction`, le point de passage de
 * `Livewire\Parametres\GestionUtilisateurs` : mêmes règles (identifiant sans arobase, unicité, rôle existant, politique
 * de mot de passe 14.65), mêmes effets (rôle, jetons révoqués à l'archivage, audit), mêmes messages.
 */
class SyncUtilisateursTest extends TestCase
{
    use RefreshDatabase;

    private const COMPTE = '77777777-7777-4777-8777-777777777777';

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $this->admin = User::create([
            'name' => 'Directeur', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('admin');
    }

    private function pousser(array $corps, ?User $qui = null): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($qui ?? $this->admin, 'sanctum')->postJson('/api/sync/push', $corps);
    }

    /** @return array<string, mixed> */
    private function compte(array $remplacements = []): array
    {
        return array_merge([
            'id' => self::COMPTE, 'name' => 'Afi DOSSOU', 'username' => 'afi', 'email' => 'afi@fermeolouwachegoun.com',
            'role' => 'caissier', 'password' => 'Caisse#2026',
        ], $remplacements);
    }

    public function test_un_compte_cree_au_poste_existe_avec_son_role_son_mot_de_passe_et_sa_trace(): void
    {
        $this->pousser(['users' => [$this->compte()]])->assertOk()->assertJsonPath('users.accepted.0', self::COMPTE);

        $u = User::find(self::COMPTE);
        $this->assertNotNull($u, "l'identifiant du poste est gardé");
        $this->assertSame('afi', $u->username);
        $this->assertTrue($u->is_active);
        $this->assertTrue($u->hasRole('caissier'));
        $this->assertTrue(Hash::check('Caisse#2026', $u->password), 'le compte créé au poste peut se connecter');
        $this->assertSame(1, AuditLog::where('action', 'user.created')->count());
    }

    public function test_un_envoi_rejoue_identique_est_acquitte_sans_rien_ecrire(): void
    {
        $this->pousser(['users' => [$this->compte()]])->assertOk();
        $avant = User::find(self::COMPTE)->password;

        // Rejoué SANS mot de passe (le poste ne le garde pas après l'acquit) : identique, rien n'est réécrit.
        $this->pousser(['users' => [$this->compte(['password' => null])]])->assertOk()->assertJsonPath('users.accepted.0', self::COMPTE);

        $this->assertSame($avant, User::find(self::COMPTE)->password);
        $this->assertSame(0, AuditLog::where('action', 'user.updated')->count());
    }

    public function test_une_modification_au_poste_change_le_role_et_le_mot_de_passe_sil_est_donne(): void
    {
        $this->pousser(['users' => [$this->compte()]])->assertOk();

        $this->pousser(['users' => [$this->compte(['name' => 'Afi DOSSOU-KPADÉ', 'role' => 'comptable', 'password' => null])]])->assertOk();
        $u = User::find(self::COMPTE);
        $this->assertSame('Afi DOSSOU-KPADÉ', $u->name);
        $this->assertTrue($u->hasRole('comptable'));
        $this->assertFalse($u->hasRole('caissier'));
        $this->assertTrue(Hash::check('Caisse#2026', $u->password), 'mot de passe absent = conservé');

        $this->pousser(['users' => [$this->compte(['name' => 'Afi DOSSOU-KPADÉ', 'role' => 'comptable', 'password' => 'Compta#2027'])]])->assertOk();
        $this->assertTrue(Hash::check('Compta#2027', User::find(self::COMPTE)->password));
        $this->assertSame(2, AuditLog::where('action', 'user.updated')->count());
    }

    public function test_un_archivage_au_poste_archive_revoque_les_jetons_puis_une_reactivation_le_rouvre(): void
    {
        $this->pousser(['users' => [$this->compte()]])->assertOk();
        $u = User::find(self::COMPTE);
        $u->createToken('poste-caisse');

        $this->pousser(['users' => [$this->compte(['password' => null, 'is_active' => false])]])->assertOk()->assertJsonPath('users.accepted.0', self::COMPTE);
        $u->refresh();
        $this->assertFalse($u->is_active);
        $this->assertSame(0, $u->tokens()->count(), 'S3 : la désactivation vaut aussi hors du web');
        $this->assertSame(1, AuditLog::where('action', 'user.archived')->count());

        // Rejoué archivé : rien de plus.
        $this->pousser(['users' => [$this->compte(['password' => null, 'is_active' => false])]])->assertOk();
        $this->assertSame(1, AuditLog::where('action', 'user.archived')->count());

        $this->pousser(['users' => [$this->compte(['password' => null, 'is_active' => true])]])->assertOk();
        $this->assertTrue($u->refresh()->is_active);
        $this->assertSame(1, AuditLog::where('action', 'user.reactivated')->count());
    }

    public function test_le_propre_compte_de_l_auteur_ne_s_archive_pas_message_du_web(): void
    {
        $reponse = $this->pousser(['users' => [[
            'id' => $this->admin->id, 'name' => 'Directeur', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com',
            'role' => 'admin', 'is_active' => false,
        ]]])->assertOk();

        $this->assertSame($this->admin->id, $reponse->json('users.rejected.0.id'));
        $this->assertStringContainsString('Vous ne pouvez pas archiver votre propre compte.', $reponse->json('users.rejected.0.reason'));
        $this->assertTrue($this->admin->refresh()->is_active);
    }

    /** @dataProvider comptesInvalides */
    public function test_un_compte_invalide_est_refuse_avec_un_motif_francais(array $remplacements, string $attendu): void
    {
        $reponse = $this->pousser(['users' => [$this->compte($remplacements)]])->assertOk();

        $this->assertSame([], $reponse->json('users.accepted'));
        $this->assertStringContainsString($attendu, $reponse->json('users.rejected.0.reason'));
        $this->assertNull(User::find(self::COMPTE));
    }

    public static function comptesInvalides(): array
    {
        return [
            'arobase dans l identifiant' => [['username' => 'afi@ferme'], "nom d'utilisateur"],
            'identifiant deja pris' => [['username' => 'admin'], 'déjà'],
            'role inconnu' => [['role' => 'auditeur'], 'rôle'],
            'mot de passe numerique (14.65)' => [['password' => '12345678'], 'mot de passe'],
            'mot de passe absent a la creation' => [['password' => null], 'mot de passe'],
            'e-mail invalide' => [['email' => 'pas-un-mail'], 'courriel'],
        ];
    }

    public function test_sans_le_droit_manage_users_les_comptes_sont_refuses(): void
    {
        $caissier = User::create(['name' => 'Caisse', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $caissier->assignRole('caissier');

        $reponse = $this->pousser(['users' => [$this->compte()]], $caissier)->assertOk();

        $this->assertSame([], $reponse->json('users.accepted'));
        $this->assertNull(User::find(self::COMPTE));
    }

    public function test_le_tirage_sert_updated_at_et_jamais_le_mot_de_passe(): void
    {
        $this->pousser(['users' => [$this->compte()]])->assertOk();

        $reponse = $this->actingAs($this->admin, 'sanctum')->getJson('/api/sync/pull')->assertOk();
        $compte = collect($reponse->json('users'))->firstWhere('id', self::COMPTE);
        $this->assertNotNull($compte['updated_at']);
        $this->assertSame('caissier', $compte['role']);
        $this->assertArrayNotHasKey('password', $compte);
        $this->assertStringNotContainsString('Caisse#2026', $reponse->getContent());
    }

    /** Le web passe par la même Action : son écran garde ses règles (identifiant, rôle, propre compte). */
    public function test_l_ecran_web_passe_par_la_meme_action(): void
    {
        \Livewire\Livewire::actingAs($this->admin)
            ->test(\App\Livewire\Parametres\GestionUtilisateurs::class)
            ->set('name', 'Afi DOSSOU')->set('username', 'afi')->set('email', 'afi@fermeolouwachegoun.com')
            ->set('role', 'caissier')->set('password', 'Caisse#2026')
            ->call('saveUser')->assertHasNoErrors();
        $this->assertTrue(User::where('username', 'afi')->first()->hasRole('caissier'));

        \Livewire\Livewire::actingAs($this->admin)
            ->test(\App\Livewire\Parametres\GestionUtilisateurs::class)
            ->call('archiveUser', $this->admin->id)
            ->assertDispatched('toast', message: 'Vous ne pouvez pas archiver votre propre compte.', type: 'error');
        $this->assertTrue($this->admin->refresh()->is_active);
    }
}
