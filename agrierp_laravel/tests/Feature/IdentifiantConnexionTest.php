<?php

namespace Tests\Feature;

use App\Livewire\Auth\Login;
use App\Livewire\Parametres\GestionUtilisateurs;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.50 (Sprint 14) — IDENTIFIANT COURT DE CONNEXION.
 *
 * Demande client : se connecter avec « admin », « compta »… plutôt qu'avec une
 * adresse complète, tapée au comptoir sur un téléphone à chaque ouverture de
 * caisse.
 *
 * ⚠️ La maquette le prévoyait DÉJÀ — son champ s'intitule « NOM D'UTILISATEUR
 * OU EMAIL » et le Blade reprenait ce libellé mot pour mot, mais n'acceptait
 * que l'e-mail. L'écran promettait ce qu'il refusait ensuite.
 *
 * Le test qui compte le plus est le dernier : un compte créé depuis l'écran
 * d'administration doit pouvoir se connecter POUR DE VRAI. Sans le champ
 * ajouté à ce formulaire, la fonctionnalité serait livrée à moitié dès le
 * premier compte créé.
 */
class IdentifiantConnexionTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-users', 'manage-users'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('admin', 'web')->givePermissionTo(['view-users', 'manage-users']);
        Role::findOrCreate('comptable', 'web');
    }

    private function admin(): User
    {
        $user = User::create([
            'name' => 'Directeur', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt(self::MDP), 'is_active' => true,
        ]);
        $user->assignRole('admin');

        return $user;
    }

    private function connecter(string $identifiant, string $motDePasse)
    {
        RateLimiter::clear($identifiant.'|127.0.0.1');

        return Livewire::test(Login::class)
            ->set('identifiant', $identifiant)
            ->set('password', $motDePasse)
            ->call('submit');
    }

    /** LE FLUX DEMANDÉ : « admin » ouvre la session. */
    public function test_the_short_username_opens_the_session(): void
    {
        $this->admin();

        $this->connecter('admin', self::MDP);

        $this->assertTrue(auth()->check());
        $this->assertEquals('admin', auth()->user()->username);
    }

    /** ⚠️ L'ADRESSE CONTINUE DE FONCTIONNER : elle n'est pas remplacée. */
    public function test_the_email_still_works(): void
    {
        $this->admin();

        $this->connecter('dg@fermeolouwachegoun.com', self::MDP);

        $this->assertTrue(auth()->check());
    }

    /** Un compte désactivé reste refusé, quel que soit l'identifiant employé. */
    public function test_an_inactive_account_is_refused_on_both_columns(): void
    {
        $this->admin()->update(['is_active' => false]);

        $this->connecter('admin', self::MDP);
        $this->assertFalse(auth()->check());

        $this->connecter('dg@fermeolouwachegoun.com', self::MDP);
        $this->assertFalse(auth()->check());
    }

    /** Le message d'erreur reste attaché au champ réellement affiché. */
    public function test_the_error_is_attached_to_the_displayed_field(): void
    {
        $this->admin();

        $this->connecter('admin', 'mauvais')->assertHasErrors('identifiant');
    }

    /**
     * ⚠️ Un identifiant court n'est PAS une adresse : aucune règle `email` ne
     * doit le rejeter avant même la tentative d'authentification. C'était
     * exactement le défaut corrigé par ce ticket.
     */
    public function test_a_short_username_is_not_rejected_as_a_malformed_email(): void
    {
        $this->admin();

        $this->connecter('admin', self::MDP)->assertHasNoErrors();
    }

    /** Le formulaire d'administration exige désormais un identifiant. */
    public function test_the_admin_form_requires_a_username(): void
    {
        $this->actingAs($this->admin());

        Livewire::test(GestionUtilisateurs::class)
            ->set('name', 'Nouvelle Caissière')
            ->set('username', '')
            ->set('email', 'caisse2@fermeolouwachegoun.com')
            ->set('role', 'comptable')
            ->set('password', 'AgriERP@2026')
            ->call('saveUser')
            ->assertHasErrors('username');
    }

    /**
     * ⚠️ LE PIÈGE QUE LA VALIDATION FERME. La connexion choisit sa colonne
     * selon la présence d'un « @ » : un identifiant qui en contiendrait serait
     * cherché parmi les ADRESSES, donc introuvable — un compte créable mais
     * inatteignable, sans le moindre message d'erreur.
     */
    public function test_an_at_sign_is_refused_in_a_username(): void
    {
        $this->actingAs($this->admin());

        Livewire::test(GestionUtilisateurs::class)
            ->set('name', 'Piège')
            ->set('username', 'compta@fermeolouwachegoun.com')
            ->set('email', 'piege@fermeolouwachegoun.com')
            ->set('role', 'comptable')
            ->set('password', 'AgriERP@2026')
            ->call('saveUser')
            ->assertHasErrors('username');
    }

    /** Deux comptes ne peuvent pas partager un identifiant. */
    public function test_a_username_is_unique(): void
    {
        $this->actingAs($this->admin());

        Livewire::test(GestionUtilisateurs::class)
            ->set('name', 'Doublon')
            ->set('username', 'admin')
            ->set('email', 'doublon@fermeolouwachegoun.com')
            ->set('role', 'comptable')
            ->set('password', 'AgriERP@2026')
            ->call('saveUser')
            ->assertHasErrors('username');
    }

    /**
     * ⚠️ LE TEST QUI FERME LA BOUCLE : un compte créé depuis l'écran
     * d'administration se connecte réellement avec son identifiant.
     */
    public function test_an_account_created_in_the_admin_screen_can_actually_sign_in(): void
    {
        $this->actingAs($this->admin());

        Livewire::test(GestionUtilisateurs::class)
            ->set('name', 'Nouvelle Caissière')
            ->set('username', 'caisse2')
            ->set('email', 'caisse2@fermeolouwachegoun.com')
            ->set('role', 'comptable')
            ->set('password', 'AgriERP@2026')
            ->call('saveUser')
            ->assertHasNoErrors();

        auth()->logout();

        $this->connecter('caisse2', 'AgriERP@2026');

        $this->assertTrue(auth()->check());
        $this->assertEquals('caisse2', auth()->user()->username);
    }
}
