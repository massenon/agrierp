<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\User;
use App\Support\PolitiqueMotDePasse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

/**
 * GAP CRITIQUE COMBLÉ — question directe de l'utilisateur, confirmé
 * absent au ticket précédent d'audit ("Communication Flutter ↔
 * Laravel — protocole documenté, API jamais construite"). `POST
 * /api/auth/login` est documenté depuis longtemps dans
 * `LARAVEL_SYNC_FLUTTER.md` mais aucun fichier `app/Http/Controllers/Api/`
 * n'existait nulle part avant ce ticket.
 *
 * Émet un vrai jeton Sanctum (`HasApiTokens`, ajouté à `User` dans ce
 * même ticket) — jamais un jeton factice. Réutilise `Hash::check()`,
 * même mécanisme que l'authentification web (Livewire `Login`), un seul
 * point de vérité pour la vérification de mot de passe.
 *
 * ⚠️ Le token est nommé d'après l'appareil (`$request->device_name`,
 * envoyé par le client Flutter) — permet de révoquer un appareil précis
 * depuis `sessions-actives`-style admin plus tard sans affecter les
 * autres, standard Sanctum multi-device.
 */
class AuthController extends Controller
{
    public function login(Request $request): JsonResponse
    {
        // 🔴→✅ TICKET 14.51 — L'API N'ACCEPTAIT QUE L'ADRESSE. Le ticket 14.50
        // a ouvert la connexion web au NOM D'UTILISATEUR court (« admin »,
        // « compta »), conformément au libellé que la maquette porte depuis
        // toujours. L'API, elle, validait `email` et cherchait sur cette seule
        // colonne : le client Flutter aurait affiché « NOM D'UTILISATEUR OU
        // EMAIL » puis se serait vu refuser « admin » par le serveur — le
        // défaut même que 14.50 corrigeait, reproduit sur l'autre surface.
        //
        // ⚠️ AUCUNE RÈGLE `email` : elle rejetterait « admin » avant même la
        // vérification du mot de passe.
        $validated = $request->validate([
            'identifiant' => ['required_without:email', 'nullable', 'string', 'max:150'],
            'email' => ['required_without:identifiant', 'nullable', 'string', 'max:150'],
            'password' => ['required', 'string'],
            'device_name' => ['required', 'string', 'max:255'],
        ]);

        // `email` reste accepté sous son ancien nom : un appareil déjà
        // déployé avec l'ancien contrat continue de fonctionner. Retirer la
        // clé aurait cassé la connexion de tout client non mis à jour.
        $identifiant = $validated['identifiant'] ?? $validated['email'];
        $colonne = str_contains($identifiant, '@') ? 'email' : 'username';

        $user = User::where($colonne, $identifiant)->first();

        if (! $user || ! Hash::check($validated['password'], $user->password)) {
            // 🔴→✅ TICKET 14.51 — L'ÉCHEC EST TRACÉ ICI AUSSI. Le ticket 14.42
            // avait comblé cet angle mort sur la connexion WEB seulement :
            // l'API restait muette, et une attaque par force brute menée
            // contre elle ne laissait aucune trace au journal d'audit. Le
            // compte visé est résolu quand l'identifiant existe.
            AuditLog::record('login.failed', 'auth', $user?->id);

            throw ValidationException::withMessages([
                'identifiant' => ['Identifiants incorrects.'],
            ]);
        }

        if (! $user->is_active) {
            AuditLog::record('login.failed', 'auth', $user->id);

            throw ValidationException::withMessages([
                'identifiant' => ['Ce compte a été désactivé. Contactez un administrateur.'],
            ]);
        }

        // Un seul jeton actif par appareil nommé — reconnecter le même
        // appareil révoque son ancien jeton plutôt que d'en accumuler.
        $user->tokens()->where('name', $validated['device_name'])->delete();

        $token = $user->createToken($validated['device_name'])->plainTextToken;

        AuditLog::record('api.login', 'auth', $user->id);

        return response()->json([
            'token' => $token,
            'user' => [
                'id' => $user->id,
                'name' => $user->name,
                'username' => $user->username,
                'email' => $user->email,
                'role' => $user->roles->first()?->name,
                'role_label' => $user->role_label,
            ],
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        AuditLog::record('api.logout', 'auth', $request->user()->id);

        return response()->json(['message' => 'Déconnexion réussie.']);
    }

    /**
     * Ticket 15.9 — CHANGEMENT DE MOT DE PASSE DEPUIS UN POSTE.
     *
     * Absent jusqu'ici : le poste affichait le formulaire de « Mon Profil »
     * sans pouvoir l'envoyer. Même contrat que la page web : l'ancien mot de
     * passe est vérifié contre le hachage réel, le nouveau suit
     * `PolitiqueMotDePasse`, l'action est journalisée `password.updated`.
     *
     * ⚠️ LES AUTRES JETONS NE SONT PAS RÉVOQUÉS. Un poste de la ferme travaille
     * hors ligne des jours durant ; lui couper son jeton le forcerait à se
     * reconnecter — donc à trouver le réseau — avant de pouvoir envoyer ses
     * ventes. Décision de sécurité à confirmer par le commanditaire.
     */
    public function changePassword(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'current_password' => ['required', 'string'],
            'new_password' => PolitiqueMotDePasse::regles(),
            'new_password_confirmation' => ['required', 'same:new_password'],
        ], array_merge(PolitiqueMotDePasse::messages(), [
            'new_password_confirmation.same' => 'La confirmation ne correspond pas au mot de passe saisi.',
        ]));

        $user = $request->user();

        if (! Hash::check($validated['current_password'], $user->password)) {
            throw ValidationException::withMessages([
                'current_password' => ["L'ancien mot de passe ne correspond pas à votre mot de passe actuel."],
            ]);
        }

        $user->forceFill(['password' => Hash::make($validated['new_password'])])->save();

        AuditLog::record('password.updated', 'auth', $user->id);

        return response()->json(['message' => 'Mot de passe mis à jour avec succès.']);
    }

    public function me(Request $request): JsonResponse
    {
        $user = $request->user();

        return response()->json([
            'id' => $user->id,
            'name' => $user->name,
            // Ticket 14.51 — meme forme que la reponse de connexion : un
            // client qui reprend sa session doit y retrouver les memes cles.
            'username' => $user->username,
            'email' => $user->email,
            'role' => $user->roles->first()?->name,
            'role_label' => $user->role_label,
            // Module « Assistant de démarrage » : un poste neuf, qui n'a encore rien tiré, le lit ici (éteint par défaut).
            'assistant_demarrage_actif' => \App\Models\ModuleConfig::isEnabled(\App\Models\ModuleConfig::ASSISTANT_DEMARRAGE),
        ]);
    }
}
