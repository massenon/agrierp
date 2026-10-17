<?php

namespace Tests\Feature;

use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Password as PasswordBroker;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.65 (Sprint 14) — POLITIQUE DE MOT DE PASSE.
 *
 * ⚠️⚠️ CE QUI ÉTAIT EN PLACE. Les deux seuls endroits qui posent un mot de
 * passe — réinitialisation et création d'un compte — exigeaient `min:8` **et
 * rien d'autre**. « 12345678 » passait. `Password::defaults()` n'apparaissait
 * nulle part dans le code.
 *
 * ⚠️ **`uncompromised()` EST VOLONTAIREMENT ABSENT** de la politique : il
 * interroge un service en ligne. Sur une ferme d'Ikpinlè dont la liaison tombe,
 * la création d'un compte deviendrait impossible — une règle de sécurité qui
 * bloque l'exploitation hors ligne serait contraire à la nature du projet.
 */
class PolitiqueMotDePasseTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        foreach (['view-parametres', 'manage-users'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('admin', 'web')->givePermissionTo(['view-parametres', 'manage-users']);

        $u = User::create([
            'name' => 'Directeur', 'username' => 'admin',
            'email' => 'dg@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole('admin');

        return $u;
    }

    /**
     * ⚠️⚠️ HUIT CHIFFRES NE SONT PLUS UN MOT DE PASSE. C'est exactement ce que
     * `min:8` seul acceptait.
     */
    public function test_a_purely_numeric_password_is_refused(): void
    {
        Livewire::actingAs($this->admin())
            ->test(\App\Livewire\Parametres\GestionUtilisateurs::class)
            ->set('name', 'Nouvel Agent')
            ->set('username', 'agent')
            ->set('email', 'agent@olouwachegoun.bj')
            ->set('password', '12345678')
            ->call('saveUser')
            ->assertHasErrors('password');

        $this->assertNull(User::where('username', 'agent')->first(),
            'aucun compte ne doit avoir ete cree');
    }

    /** Un mot de passe sans chiffre ni symbole est refusé de même. */
    public function test_letters_alone_are_refused(): void
    {
        Livewire::actingAs($this->admin())
            ->test(\App\Livewire\Parametres\GestionUtilisateurs::class)
            ->set('name', 'Nouvel Agent')
            ->set('username', 'agent')
            ->set('email', 'agent@olouwachegoun.bj')
            ->set('password', 'motdepasse')
            ->call('saveUser')
            ->assertHasErrors('password');
    }

    /**
     * ⚠️ LE MOT DE PASSE DES COMPTES DE DÉMONSTRATION RESTE VALIDE. Une
     * politique qui invaliderait `AgriERP@2026` casserait la recette et la
     * formation du personnel le jour de sa mise en place.
     */
    public function test_the_demo_password_still_passes(): void
    {
        Livewire::actingAs($this->admin())
            ->test(\App\Livewire\Parametres\GestionUtilisateurs::class)
            ->set('name', 'Nouvel Agent')
            ->set('username', 'agent')
            ->set('email', 'agent@olouwachegoun.bj')
            ->set('password', 'AgriERP@2026')
            ->call('saveUser')
            ->assertHasNoErrors('password');
    }

    /**
     * ⚠️ LA RÉINITIALISATION APPLIQUE LA MÊME RÈGLE. Protéger la création sans
     * protéger la réinitialisation laisserait la porte grande ouverte : c'est
     * le chemin qu'emprunte un utilisateur qui a perdu son mot de passe.
     */
    public function test_the_reset_screen_applies_the_same_policy(): void
    {
        $utilisateur = User::create([
            'name' => 'Caissier', 'username' => 'caisse',
            'email' => 'caisse@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);

        $jeton = PasswordBroker::createToken($utilisateur);

        Livewire::test(\App\Livewire\Auth\ResetPassword::class, [
            'token' => $jeton,
        ])
            ->set('email', $utilisateur->email)
            ->set('password', '12345678')
            ->set('password_confirmation', '12345678')
            ->call('submit')
            ->assertHasErrors('password');

        $this->assertTrue(Hash::check('AgriERP@2026', $utilisateur->fresh()->password),
            'le mot de passe ne doit pas avoir change');
    }
}
