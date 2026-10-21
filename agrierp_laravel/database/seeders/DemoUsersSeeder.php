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
            // Décision client du 17/10/2026 : « M. Olouchègoun », adresse de contact du domaine de la ferme.
            ['name' => 'M. Olouchègoun', 'username' => 'admin', 'email' => 'contact@fermeolouwachegoun.com', 'role' => 'admin'],
            ['name' => 'Comptable Ferme École', 'username' => 'compta', 'email' => 'compta@fermeolouwachegoun.com', 'role' => 'comptable'],
            ['name' => 'Caissière POS', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com', 'role' => 'caissier'],
            ['name' => 'Chef d\'Élevage', 'username' => 'elevage', 'email' => 'elevage@fermeolouwachegoun.com', 'role' => 'animalier'],
        ];

        foreach ($accounts as $account) {
            // ⚠️ RETROUVÉ PAR L'IDENTIFIANT, PLUS PAR L'E-MAIL (17/10/2026) : l'e-mail de l'administrateur a changé
            // (dg@olouwachegoun.bj → contact@fermeolouwachegoun.com). Cherché par e-mail, le compte existant n'était
            // plus trouvé et la création d'un second « admin » échouait sur l'unicité de `username`. Un compte
            // existant reçoit le nom et l'e-mail à jour ; son mot de passe n'est jamais touché.
            $user = User::firstOrCreate(
                ['username' => $account['username']],
                [
                    'name' => $account['name'],
                    'email' => $account['email'],
                    'password' => Hash::make('AgriERP@2026'),
                    'email_verified_at' => now(),
                    'is_active' => true,
                ]
            );
            $user->fill(['name' => $account['name'], 'email' => $account['email']]);
            if ($user->isDirty()) {
                $user->save();
            }

            if (! $user->hasRole($account['role'])) {
                $user->assignRole($account['role']);
            }
        }
    }
}
