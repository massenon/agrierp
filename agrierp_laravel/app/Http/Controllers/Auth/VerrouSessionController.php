<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Services\VerrouSessionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;

/**
 * Sprint VW (VW1) — les deux actions du verrou de session web : `POST /verrouiller` (appelé par le menu « Verrouiller »
 * et par la minuterie d'inactivité) et `POST /deverrouiller` (la surcouche, ou le formulaire de la page de
 * verrouillage). Toute la règle est dans `VerrouSessionService`.
 *
 * Contrat JSON de `/deverrouiller` : 200 `{verrouille:false, retour}` · 422 `{message}` (mot de passe vide ou
 * incorrect) · 429 `{message, secondes}` (limiteur) · 401 `{deconnecte:true, message, redirect}` (10 échecs).
 */
class VerrouSessionController extends Controller
{
    public function __construct(private readonly VerrouSessionService $service) {}

    public function verrouiller(Request $request): JsonResponse|RedirectResponse
    {
        $this->service->verrouiller($request->user());

        return $request->expectsJson()
            ? response()->json(['verrouille' => true])
            : redirect()->route('session.verrou');
    }

    public function deverrouiller(Request $request): JsonResponse|RedirectResponse
    {
        $motDePasse = (string) $request->input('password', '');

        if ($motDePasse === '') {
            return $this->echec($request, 'Le mot de passe est obligatoire.', 422);
        }

        $resultat = $this->service->deverrouiller($request->user(), $motDePasse);

        return match ($resultat['statut']) {
            'ok' => $this->succes($request),
            'temporise' => $this->echec(
                $request,
                "Trop d'essais. Réessayez dans ".VerrouSessionService::formaterAttente($resultat['secondes']).'.',
                429,
                ['secondes' => $resultat['secondes']],
            ),
            'deconnecte' => $this->deconnecte($request),
            default => $this->echec($request, 'Mot de passe incorrect.', 422),
        };
    }

    private function succes(Request $request): JsonResponse|RedirectResponse
    {
        $retour = $this->service->retour();

        return $request->expectsJson()
            ? response()->json(['verrouille' => false, 'retour' => $retour])
            : redirect()->to($retour);
    }

    private function echec(Request $request, string $message, int $statut, array $plus = []): JsonResponse|RedirectResponse
    {
        return $request->expectsJson()
            ? response()->json(['message' => $message, ...$plus], $statut)
            : redirect()->route('session.verrou')->withErrors(['password' => $message]);
    }

    private function deconnecte(Request $request): JsonResponse|RedirectResponse
    {
        $message = "Trop d'échecs : vous avez été déconnecté. Reconnectez-vous.";
        session()->flash('toast', ['message' => $message, 'type' => 'error']);

        return $request->expectsJson()
            ? response()->json(['message' => $message, 'deconnecte' => true, 'redirect' => route('login')], 401)
            : redirect()->route('login');
    }
}
