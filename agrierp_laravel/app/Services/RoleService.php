<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\Role;
use App\Models\User;
use Illuminate\Validation\ValidationException;

/**
 * Ticket PA-2 — POINT DE PASSAGE UNIQUE DES RÔLES (créer, modifier, supprimer) : `Parametres\RolesPermissions` ET l'envoi du
 * poste (type `role` de `settings_requests`). Réservé à l'administrateur ; les quatre rôles fondamentaux ne se suppriment
 * jamais ; un rôle encore porté par un utilisateur actif ne se supprime pas.
 */
class RoleService
{
    public const FONDAMENTAUX = ['admin', 'comptable', 'caissier', 'animalier'];

    public const MESSAGE_NOM = 'Le nom du rôle ne doit contenir que des lettres minuscules, chiffres et tirets (ex : responsable-achats).';

    /** @return array<string, array<int, string>> */
    public function regles(?string $ancienNom): array
    {
        return [
            'roleName' => [
                'required', 'string', 'max:50', 'regex:/^[a-z0-9\-]+$/',
                $ancienNom
                    ? 'unique:roles,name,'.Role::where('name', $ancienNom)->value('id')
                    : 'unique:roles,name',
            ],
        ];
    }

    /** @param array<int, string> $permissions noms accordés */
    public function enregistrer(?string $ancienNom, string $nom, array $permissions, ?User $auteur): Role
    {
        $this->reserverAdmin($auteur);

        if ($ancienNom !== null) {
            $role = Role::where('name', $ancienNom)->firstOrFail();
            $role->update(['name' => $nom]);
            $role->syncPermissions($permissions);
            AuditLog::record('role.updated', 'parametres');

            return $role;
        }

        $role = Role::create(['name' => $nom, 'guard_name' => 'web']);
        $role->syncPermissions($permissions);
        AuditLog::record('role.created', 'parametres');

        return $role;
    }

    /**
     * @return string|null le motif du refus, ou null quand le rôle est supprimé (ou déjà absent)
     */
    public function supprimer(string $nom, ?User $auteur): ?string
    {
        $this->reserverAdmin($auteur);

        if (in_array($nom, self::FONDAMENTAUX, true)) {
            return "Le rôle « {$nom} » fait partie des 4 rôles fondamentaux du système et ne peut jamais être supprimé.";
        }

        $role = Role::where('name', $nom)->first();

        if (! $role) {
            return null;
        }

        $porteurs = User::role($role->name)->where('is_active', true)->count();   // compte archivé exclu

        if ($porteurs > 0) {
            return "Impossible de supprimer « {$role->name} » : {$porteurs} utilisateur(s) porte(nt) encore ce rôle.";
        }

        $role->delete();
        AuditLog::record('role.deleted', 'parametres');

        return null;
    }

    private function reserverAdmin(?User $auteur): void
    {
        if (! ($auteur?->hasRole('admin') ?? false)) {
            throw ValidationException::withMessages(['roleName' => "Seul l'administrateur peut gérer les rôles."]);
        }
    }
}
