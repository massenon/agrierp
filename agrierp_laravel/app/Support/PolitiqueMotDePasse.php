<?php

namespace App\Support;

/**
 * Ticket 15.9 — POLITIQUE DE MOT DE PASSE DU CHANGEMENT DEPUIS « MON PROFIL ».
 *
 * ⚠️ DÉCISION DU COMMANDITAIRE : 8 caractères, une majuscule, un chiffre — la
 * règle que le prototype annonce dans le champ (« Min. 8 caractères, 1
 * majuscule, 1 chiffre »). Elle remplace le `min:8` seul de `MonProfil`, qui
 * s'appuyait sur le Document 06 §12.
 *
 * Un seul point de vérité pour les DEUX surfaces qui changent un mot de passe
 * depuis le profil (page web Livewire et `POST /api/auth/password`) : deux
 * règles distinctes laisseraient le poste accepter ce que le web refuse, ou
 * l'inverse.
 *
 * ⚠️ NE TOUCHE PAS à `Password::defaults()` (ticket 14.65), qui gouverne la
 * réinitialisation et la création d'utilisateur et exige en plus un symbole :
 * cette divergence-là reste à arbitrer, elle n'est pas résolue ici.
 */
class PolitiqueMotDePasse
{
    public static function regles(): array
    {
        return ['required', 'string', 'min:8', 'regex:/[A-Z]/', 'regex:/[0-9]/'];
    }

    public static function messages(string $champ = 'new_password'): array
    {
        return [
            "$champ.min" => 'Le mot de passe doit contenir au moins 8 caractères.',
            "$champ.regex" => 'Le mot de passe doit contenir au moins une majuscule et un chiffre.',
        ];
    }
}
