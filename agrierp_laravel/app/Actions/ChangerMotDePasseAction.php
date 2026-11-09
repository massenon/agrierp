<?php

namespace App\Actions;

use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

/**
 * Ticket MDP-1 — POINT DE PASSAGE UNIQUE du CHANGEMENT de mot de passe par son titulaire : « Mon Profil » (web),
 * la page de changement obligatoire (web) et `POST /api/auth/password` (poste).
 *
 * Effets : mot de passe haché, `must_change_password` remis à faux, ligne d'audit `password.updated` (jamais le mot
 * de passe). Quand le compte DOIT changer son mot de passe (temporaire posé par un administrateur), le nouveau doit
 * différer du temporaire : sinon le geste de l'administrateur ne protégerait rien.
 */
class ChangerMotDePasseAction
{
    public const MESSAGE_IDENTIQUE_AU_TEMPORAIRE = 'Le nouveau mot de passe doit être différent du mot de passe temporaire.';

    /** @throws ValidationException le nouveau mot de passe est celui que l'administrateur a donné. */
    public function executer(User $utilisateur, string $nouveau, string $champ = 'new_password'): void
    {
        if ($utilisateur->must_change_password && Hash::check($nouveau, $utilisateur->password)) {
            throw ValidationException::withMessages([$champ => self::MESSAGE_IDENTIQUE_AU_TEMPORAIRE]);
        }

        $utilisateur->forceFill([
            'password' => Hash::make($nouveau),
            'must_change_password' => false,
        ])->save();

        AuditLog::record('password.updated', 'auth', $utilisateur->id);
    }
}
