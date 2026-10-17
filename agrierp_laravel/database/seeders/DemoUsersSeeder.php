<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

/**
 * Comptes de démonstration — Document 08 §6 (08_MIGRATION_DEPLOYMENT.md) :
 * exactement 4 comptes, un par rôle RBAC réel. Directeur Général et Support
 * Technique partagent le rôle `admin` — un seul compte `admin` suffit.
 *
 * Ces mots de passe sont des identifiants de DÉMONSTRATION pour
 * l'environnement de développement uniquement — à changer immédiatement en
 * production réelle (Document 08 §11, déjà signalé dans ce même document).
 */
class DemoUsersSeeder extends Seeder
{
    public function run(): void
    {
        $accounts = [
            ['name' => 'M. OLOUKOUNLE Olouchègoun Hassimiyou', 'username' => 'admin', 'email' => 'dg@olouwachegoun.bj', 'role' => 'admin'],
            ['name' => 'Comptable Ferme École', 'username' => 'compta', 'email' => 'compta@olouwachegoun.bj', 'role' => 'comptable'],
            ['name' => 'Caissière POS', 'username' => 'caisse', 'email' => 'caisse@olouwachegoun.bj', 'role' => 'caissier'],
            ['name' => 'Chef d\'Élevage', 'username' => 'elevage', 'email' => 'elevage@olouwachegoun.bj', 'role' => 'animalier'],
        ];

        foreach ($accounts as $account) {
            $user = User::firstOrCreate(
                ['email' => $account['email']],
                [
                    'name' => $account['name'],
                    // Ticket 14.50 — identifiant court de connexion.
                    'username' => $account['username'],
                    'password' => Hash::make('AgriERP@2026'),
                    'email_verified_at' => now(),
                    'is_active' => true,
                ]
            );

            if (! $user->hasRole($account['role'])) {
                $user->assignRole($account['role']);
            }
        }
    }
}
