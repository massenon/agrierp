<?php

namespace Tests\Feature;

use App\Actions\SaisieUtilisateurAction;
use App\Livewire\Parametres\GestionUtilisateurs;
use App\Models\AuditLog;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket MDP-1 — « Réinitialiser le mot de passe » par un administrateur (web, `GestionUtilisateurs`).
 *
 * Le client abandonne la réinitialisation par e-mail : l'administrateur choisit un mot de passe TEMPORAIRE, le compte est
 * marqué `must_change_password`, ses jetons et sessions sont fermés, une ligne d'audit dit QUI a réinitialisé QUEL compte
 * (jamais le mot de passe). Un administrateur ne réinitialise pas son propre compte (refus serveur ET écran).
 */
class ReinitialisationMotDePasseAdminTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $caissier;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);

        $this->admin = User::create(['name' => 'Directeur', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $this->admin->assignRole('admin');
        $this->caissier = User::create(['name' => 'Afi', 'username' => 'afi', 'email' => 'afi@fermeolouwachegoun.com', 'password' => bcrypt('Ancien#2026'), 'is_active' => true]);
        $this->caissier->assignRole('caissier');
    }

    private function ecran()
    {
        return Livewire::actingAs($this->admin)->test(GestionUtilisateurs::class);
    }

    public function test_la_reinitialisation_pose_le_temporaire_le_drapeau_ferme_jetons_et_sessions_et_trace_sans_secret(): void
    {
        $this->caissier->createToken('poste-caisse');
        DB::table('sessions')->insert(['id' => 'sess-afi', 'user_id' => $this->caissier->id, 'payload' => 'x', 'last_activity' => time()]);
        DB::table('sessions')->insert(['id' => 'sess-admin', 'user_id' => $this->admin->id, 'payload' => 'x', 'last_activity' => time()]);

        $this->ecran()
            ->call('resetPasswordUser', $this->caissier->id)
            ->set('motDePasseTemporaire', 'Temp#Ferme2026')
            ->call('reinitialiserMotDePasse')
            ->assertHasNoErrors()
            ->assertDispatched('toast');

        $u = $this->caissier->fresh();
        $this->assertTrue($u->must_change_password, 'le drapeau est posé');
        $this->assertTrue(Hash::check('Temp#Ferme2026', $u->password), 'le temporaire est le mot de passe du compte');
        $this->assertFalse(Hash::check('Ancien#2026', $u->password));
        $this->assertSame(0, $u->tokens()->count(), 'jetons Sanctum révoqués');
        $this->assertNull(DB::table('sessions')->where('id', 'sess-afi')->first(), 'sessions web du compte fermées');
        $this->assertNotNull(DB::table('sessions')->where('id', 'sess-admin')->first(), "celles de l'administrateur restent");

        $trace = AuditLog::where('action', 'user.password_reset')->get();
        $this->assertCount(1, $trace);
        $this->assertSame($this->admin->id, $trace[0]->user_id, 'qui a réinitialisé');
        $this->assertSame($this->caissier->id, $trace[0]->entity_id, 'quel compte');
        $this->assertStringNotContainsString('Temp#Ferme2026', json_encode(AuditLog::all()->toArray()), 'jamais le mot de passe dans le journal');
    }

    public function test_un_administrateur_ne_peut_pas_reinitialiser_son_propre_compte_ecran_et_serveur(): void
    {
        // Écran : refus dès l'ouverture, avec le message français.
        $this->ecran()
            ->call('resetPasswordUser', $this->admin->id)
            ->assertDispatched('toast', message: SaisieUtilisateurAction::MESSAGE_PROPRE_REINITIALISATION, type: 'error')
            ->assertSet('resetUserId', null);

        // Serveur : même en forçant l'identifiant, rien n'est écrit.
        $this->ecran()
            ->set('resetUserId', $this->admin->id)
            ->set('motDePasseTemporaire', 'Temp#Ferme2026')
            ->call('reinitialiserMotDePasse')
            ->assertDispatched('toast', message: SaisieUtilisateurAction::MESSAGE_PROPRE_REINITIALISATION, type: 'error');

        $this->assertFalse($this->admin->fresh()->must_change_password);
        $this->assertTrue(Hash::check('AgriERP@2026', $this->admin->fresh()->password));
        $this->assertSame(0, AuditLog::where('action', 'user.password_reset')->count());

        // L'action seule refuse aussi (appelée par l'envoi des postes).
        $this->expectException(\Illuminate\Validation\ValidationException::class);
        app(SaisieUtilisateurAction::class)->reinitialiserMotDePasse($this->admin->id, 'Temp#Ferme2026', $this->admin->id);
    }

    public function test_le_mot_de_passe_temporaire_suit_la_politique_de_creation(): void
    {
        foreach (['12345678', 'motdepasse', 'Court#1', ''] as $faible) {
            $this->ecran()
                ->call('resetPasswordUser', $this->caissier->id)
                ->set('motDePasseTemporaire', $faible)
                ->call('reinitialiserMotDePasse')
                ->assertHasErrors('motDePasseTemporaire');
        }

        $this->assertFalse($this->caissier->fresh()->must_change_password);
        $this->assertTrue(Hash::check('Ancien#2026', $this->caissier->fresh()->password));
    }

    public function test_un_compte_archive_n_est_pas_reinitialisable(): void
    {
        $this->caissier->update(['is_active' => false]);

        $this->ecran()
            ->set('resetUserId', $this->caissier->id)
            ->set('motDePasseTemporaire', 'Temp#Ferme2026')
            ->call('reinitialiserMotDePasse')
            ->assertDispatched('toast', message: SaisieUtilisateurAction::MESSAGE_COMPTE_ARCHIVE_REINITIALISATION, type: 'error');

        $this->assertFalse($this->caissier->fresh()->must_change_password);
    }

    public function test_sans_manage_users_le_geste_est_refuse(): void
    {
        $this->caissier->givePermissionTo('view-ventes');

        Livewire::actingAs($this->caissier)->test(GestionUtilisateurs::class)
            ->call('resetPasswordUser', $this->admin->id)
            ->assertForbidden();

        $this->assertFalse($this->admin->fresh()->must_change_password);
    }

    public function test_la_liste_montre_le_compte_dont_le_mot_de_passe_est_a_changer(): void
    {
        $this->ecran()->assertDontSee('Mot de passe à changer');

        $this->caissier->forceFill(['must_change_password' => true])->save();

        $this->ecran()->assertSee('Mot de passe à changer')->assertSee('Réinitialiser le mot de passe');
    }

    public function test_un_renvoi_du_meme_temporaire_n_ecrit_ni_ne_retrace_rien(): void
    {
        $action = app(SaisieUtilisateurAction::class);
        $this->assertTrue($action->reinitialiserMotDePasse($this->caissier->id, 'Temp#Ferme2026', $this->admin->id));
        $this->assertFalse($action->reinitialiserMotDePasse($this->caissier->id, 'Temp#Ferme2026', $this->admin->id));

        $this->assertSame(1, AuditLog::where('action', 'user.password_reset')->count());
    }
}
