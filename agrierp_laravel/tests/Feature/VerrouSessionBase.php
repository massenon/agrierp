<?php

namespace Tests\Feature;

use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * Sprint VW — socle commun des tests du verrou de session web : un compte réel, connecté, et le
 * moyen de poser l'état « verrouillé » dans SA session comme le ferait `POST /verrouiller`.
 */
abstract class VerrouSessionBase extends TestCase
{
    use RefreshDatabase;

    protected const MOT_DE_PASSE = 'AgriERP@2026';

    protected function utilisateur(string $role = 'admin', string $username = 'admin'): User
    {
        $this->seed(RolesAndPermissionsSeeder::class);

        $u = User::create([
            'name' => 'M. Olouchègoun',
            'username' => $username,
            'email' => $username.'@fermeolouwachegoun.com',
            'password' => Hash::make(self::MOT_DE_PASSE),
            'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    /** Un compte connecté dont la session est déjà verrouillée. */
    protected function verrouille(string $role = 'admin', string $username = 'admin'): User
    {
        $u = $this->utilisateur($role, $username);
        $this->actingAs($u)->withSession(['session_locked' => true]);

        return $u;
    }

    /** Clé du limiteur de déverrouillage de ce compte (adresse de test 127.0.0.1). */
    protected function cleLimiteur(User $u): string
    {
        return \App\Services\VerrouSessionService::cleLimiteur($u->id, '127.0.0.1');
    }
}
