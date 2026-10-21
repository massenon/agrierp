<?php

namespace Tests\Feature;

use App\Models\User;
use Database\Seeders\DemoUsersSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * Ticket ENV1 (demande 1) — « M. Olouchègoun » est le compte administrateur principal.
 *
 * Seul le NOM D'AFFICHAGE est en jeu : l'identifiant `admin`, le rôle, les droits, le mot de passe et la
 * connexion ne changent pas. Les autres comptes de démonstration ne sont pas touchés.
 */
class AdministrateurPrincipalNomTest extends TestCase
{
    use RefreshDatabase;

    public function test_le_seeder_nomme_l_administrateur_sans_changer_son_identifiant_ni_ses_droits(): void
    {
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(DemoUsersSeeder::class);

        $admin = User::where('username', 'admin')->firstOrFail();
        $this->assertSame('M. Olouchègoun', $admin->name);
        $this->assertTrue($admin->hasRole('admin'));
        $this->assertTrue($admin->is_active);
        $this->assertTrue(Hash::check('AgriERP@2026', $admin->password));

        // Les trois autres comptes gardent leur nom.
        $this->assertSame('Comptable Ferme École', User::where('username', 'compta')->value('name'));
        $this->assertSame('Caissière POS', User::where('username', 'caisse')->value('name'));
        $this->assertSame("Chef d'Élevage", User::where('username', 'elevage')->value('name'));
    }

    public function test_une_base_existante_reprend_le_nom_sans_toucher_au_mot_de_passe(): void
    {
        $this->seed(RolesAndPermissionsSeeder::class);
        $ancien = User::create([
            'name' => 'Manager Olouwachegoun', 'username' => 'admin', 'email' => 'dg@olouwachegoun.bj',
            'password' => Hash::make('MotDePasseChoisiParLeClient1'), 'is_active' => true,
        ]);

        $this->seed(DemoUsersSeeder::class);

        $this->assertSame(1, User::where('username', 'admin')->count());
        $admin = $ancien->fresh();
        $this->assertSame('M. Olouchègoun', $admin->name);
        $this->assertTrue(Hash::check('MotDePasseChoisiParLeClient1', $admin->password));
    }

    public function test_la_connexion_par_l_identifiant_admin_fonctionne_et_renvoie_le_nom(): void
    {
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(DemoUsersSeeder::class);

        $reponse = $this->postJson('/api/auth/login', [
            'identifiant' => 'admin', 'password' => 'AgriERP@2026', 'device_name' => 'poste-test',
        ]);

        $reponse->assertOk();
        $this->assertSame('M. Olouchègoun', $reponse->json('user.name'));
    }
}
