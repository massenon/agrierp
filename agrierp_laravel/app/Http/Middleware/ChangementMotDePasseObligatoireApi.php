<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Ticket MDP-1 — le jeton d'un compte dont le mot de passe est TEMPORAIRE (`must_change_password`) ne sert qu'à changer
 * ce mot de passe : tout le reste de l'API (tirage, envoi, pièces, administration…) répond 403 avec un motif français
 * que le poste affiche tel quel. Restent joignables : `POST /api/auth/password`, `GET /api/auth/me`,
 * `POST /api/auth/logout`.
 *
 * Posé à la suite de `CompteActif` dans le groupe Sanctum de `routes/api.php`.
 */
class ChangementMotDePasseObligatoireApi
{
    public function handle(Request $request, Closure $next): Response
    {
        $utilisateur = $request->user();

        if ($utilisateur && $utilisateur->must_change_password
            && ! $request->is('api/auth/password', 'api/auth/me', 'api/auth/logout')) {
            return response()->json([
                'message' => 'Vous devez changer votre mot de passe temporaire avant de continuer.',
                'must_change_password' => true,
            ], 403);
        }

        return $next($request);
    }
}
