<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Laravel\Sanctum\PersonalAccessToken;
use Symfony\Component\HttpFoundation\Response;

/**
 * Ticket S3 — un compte désactivé ne travaille plus par l'API, même avec un jeton encore valide.
 *
 * 🔴 `is_active` n'était vérifié qu'à la connexion (`AuthController::login`) : un poste déjà connecté
 * continuait de tirer et de pousser après la désactivation du compte sur le web. Le jeton présenté est
 * révoqué et la réponse est un 403 motivé, que le poste affiche tel quel.
 */
class CompteActif
{
    public function handle(Request $request, Closure $next): Response
    {
        $utilisateur = $request->user();

        if ($utilisateur && ! $utilisateur->is_active) {
            $jeton = $utilisateur->currentAccessToken();
            if ($jeton instanceof PersonalAccessToken) {
                $jeton->delete();
            }

            return response()->json([
                'message' => "Compte désactivé : contactez l'administrateur de la ferme.",
            ], 403);
        }

        return $next($request);
    }
}
