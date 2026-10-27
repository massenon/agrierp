<?php

namespace App\Actions;

use App\Models\AuditLog;
use App\Models\Role;
use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password as PasswordRule;
use Illuminate\Validation\ValidationException;

/**
 * Ticket UT-1 — POINT DE PASSAGE UNIQUE d'un compte utilisateur : création, modification, archivage, réactivation.
 *
 * Ces gestes vivaient dans `Livewire\Parametres\GestionUtilisateurs`. Le poste crée, modifie, archive et réactive
 * désormais ses utilisateurs (hors ligne, rejoués à l'envoi par `SyncController::pushUsers`, droit `manage-users`) :
 * les deux chemins passent ici, avec les mêmes règles, les mêmes effets (rôle, jetons révoqués, audit) et les mêmes
 * messages.
 *
 * Règles :
 *  - création : nom, identifiant court (sans arobase : la connexion choisit sa colonne selon « @ »), e-mail, rôle
 *    EXISTANT, mot de passe selon `Password::defaults()` (14.65 : « 12345678 » refusé) ; `is_active` vrai ;
 *  - modification : mêmes règles ; le mot de passe est FACULTATIF (vide = conservé) ; une modification identique
 *    n'écrit rien (idempotence des renvois) ;
 *  - archivage : `is_active = false`, jetons des postes révoqués (S3 : la désactivation vaut aussi hors du web) ;
 *    ⚠️ un compte ne s'archive JAMAIS lui-même (il n'aurait personne pour le réactiver) ; un second archivage n'a
 *    aucun effet, ni trace ;
 *  - réactivation : `is_active = true` ; une seconde réactivation n'a aucun effet, ni trace.
 *
 * ⚠️ Le mot de passe n'est JAMAIS journalisé ni renvoyé : il n'existe qu'haché.
 */
class SaisieUtilisateurAction
{
    public const MESSAGE_PROPRE_COMPTE = 'Vous ne pouvez pas archiver votre propre compte.';

    /** Règles de validation du web (`GestionUtilisateurs::saveUser`), sous les clés de la table. */
    public static function regles(?string $id = null, bool $creation = true): array
    {
        return [
            'name' => ['required', 'string', 'max:150'],
            // ⚠️ `regex` INTERDISANT L'ARROBASE : la connexion choisit sa colonne selon la présence d'un « @ ». Un
            // identifiant qui en contiendrait serait cherché parmi les ADRESSES, donc introuvable.
            'username' => ['required', 'string', 'min:3', 'max:50', 'regex:/^[a-zA-Z0-9._-]+$/', 'unique:users,username,'.$id],
            'email' => ['required', 'email', 'max:150', 'unique:users,email,'.$id],
            'role' => ['required', 'exists:roles,name'],
            // ⚠️ TICKET 14.65 — même politique qu'à la réinitialisation : `min:8` seul laissait passer « 12345678 ».
            'password' => [$creation ? 'required' : 'nullable', 'string', PasswordRule::defaults()],
        ];
    }

    /** Les noms de rôle que l'écran propose (`Role::pluck('name')`), jamais une liste en dur. */
    public static function roles(): array
    {
        return Role::query()->orderBy('name')->pluck('name')->all();
    }

    /**
     * Crée le compte avec `is_active` vrai ; `$id` est l'UUID choisi par le poste (jamais régénéré), sinon tiré ici.
     *
     * @param  array{name: string, username: string, email: string, role: string, password: string}  $donnees
     */
    public function creer(array $donnees, ?string $id = null): User
    {
        $utilisateur = new User();
        if ($id !== null) {
            // ⚠️ `id` n'est pas remplissable : `create(['id' => …])` l'ignorerait en silence (piège 14.78).
            $utilisateur->id = $id;
        }
        $utilisateur->fill([
            'name' => $donnees['name'],
            'username' => $donnees['username'],
            'email' => $donnees['email'],
            'password' => Hash::make($donnees['password']),
            'is_active' => true,
        ]);
        $utilisateur->save();
        $utilisateur->assignRole($donnees['role']);
        AuditLog::record('user.created', 'parametres');

        return $utilisateur;
    }

    /**
     * Modifie nom, identifiant, e-mail, rôle ; le mot de passe seulement s'il est donné.
     *
     * @param  array{name: string, username: string, email: string, role: string, password?: string|null}  $donnees
     */
    public function modifier(string $id, array $donnees): User
    {
        $utilisateur = User::findOrFail($id);
        $charge = [
            'name' => $donnees['name'],
            'username' => $donnees['username'],
            'email' => $donnees['email'],
        ];
        if (! empty($donnees['password'])) {
            $charge['password'] = Hash::make($donnees['password']);
        }
        $utilisateur->update($charge);
        $utilisateur->syncRoles([$donnees['role']]);
        AuditLog::record('user.updated', 'parametres');

        return $utilisateur;
    }

    /** Vrai si la ligne porte déjà ces valeurs (sans mot de passe donné) : rien à écrire. */
    public function identique(User $utilisateur, array $donnees): bool
    {
        return empty($donnees['password'])
            && $utilisateur->name === $donnees['name']
            && (string) $utilisateur->username === (string) $donnees['username']
            && $utilisateur->email === $donnees['email']
            && $utilisateur->roles->first()?->name === $donnees['role'];
    }

    /**
     * Archive le compte et révoque ses jetons ; refuse le propre compte de l'auteur.
     *
     * @return bool Vrai si le compte a été archivé par cet appel ; faux s'il l'était déjà.
     *
     * @throws ValidationException quand `$id` est le compte de `$auteurId` (message du web).
     */
    public function archiver(string $id, ?string $auteurId): bool
    {
        if ($auteurId !== null && $id === $auteurId) {
            throw ValidationException::withMessages(['id' => self::MESSAGE_PROPRE_COMPTE]);
        }

        $utilisateur = User::findOrFail($id);
        if (! $utilisateur->is_active) {
            return false;
        }
        $utilisateur->update(['is_active' => false]);
        // Ticket S3 — les jetons de ses postes sont révoqués : la désactivation vaut aussi hors du web.
        $utilisateur->tokens()->delete();
        AuditLog::record('user.archived', 'parametres', null, $utilisateur);

        return true;
    }

    /** @return bool Vrai si le compte a été réactivé par cet appel ; faux s'il l'était déjà. */
    public function reactiver(string $id): bool
    {
        $utilisateur = User::findOrFail($id);
        if ($utilisateur->is_active) {
            return false;
        }
        $utilisateur->update(['is_active' => true]);
        AuditLog::record('user.reactivated', 'parametres');

        return true;
    }
}
