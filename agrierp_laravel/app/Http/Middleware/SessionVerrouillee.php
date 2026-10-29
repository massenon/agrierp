<?php

namespace App\Http\Middleware;

use App\Services\VerrouSessionService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Sprint VW (VW1) — tant que la session est verrouillée, AUCUNE requête web n'aboutit : ni page, ni envoi Livewire
 * (`POST /livewire/update`), ni téléversement, ni formulaire.
 *
 * ⚠️ C'EST LE SERVEUR QUI REFUSE, pas la surcouche du navigateur : un navigateur manipulé (surcouche retirée dans les
 * outils de développement, requête rejouée à la main) n'obtient rien de plus.
 *
 *  - requête JavaScript / Livewire / JSON : **423 Locked** (`verrouille: true`) — le navigateur y répond en affichant
 *    la surcouche, jamais une page d'erreur ;
 *  - page (GET) : redirection vers l'écran de verrouillage, en mémorisant la page demandée pour le retour ;
 *  - autre requête (POST de formulaire) : redirection, sans mémoriser (rejouer une écriture à l'aveugle est dangereux).
 *
 * Exempts : l'écran et l'action de déverrouillage, le verrouillage lui-même (idempotent), la déconnexion, les pages
 * publiques, la sonde `/up` et les fichiers JavaScript de Livewire. Un visiteur non connecté n'est jamais concerné
 * (l'état est tenu pour périmé). Les routes d'API du poste n'ont pas de session : elles n'entrent pas dans le groupe
 * `web`, donc pas ici.
 */
class SessionVerrouillee
{
    /** Noms de routes qui doivent rester joignables session verrouillée. */
    private const ROUTES_EXEMPTES = [
        'session.verrou',
        'session.deverrouiller',
        'session.verrouiller',
        'logout',
        'login',
        'public.welcome',
        'public.presentation',
        'health-check',
    ];

    public function handle(Request $request, Closure $next): Response
    {
        if (! VerrouSessionService::estVerrouillee() || ! $request->user() || $this->estExempte($request)) {
            return $next($request);
        }

        if ($request->expectsJson() || $request->headers->has('X-Livewire') || $request->ajax()) {
            return response()->json([
                'message' => 'Session verrouillée.',
                'verrouille' => true,
                'url' => route('session.verrou'),
            ], 423);
        }

        if ($request->isMethod('GET') && ! $request->headers->has('X-Livewire')) {
            session([VerrouSessionService::CLE_RETOUR => $request->fullUrl()]);
        }

        return redirect()->route('session.verrou');
    }

    private function estExempte(Request $request): bool
    {
        $nom = $request->route()?->getName();
        if ($nom !== null && in_array($nom, self::ROUTES_EXEMPTES, true)) {
            return true;
        }

        // Fichiers JavaScript de Livewire (route sans nom stable) : jamais `/livewire/update`.
        return $request->is('livewire/livewire.js', 'livewire/livewire.min.js.map', 'livewire/livewire.csp.min.js', 'livewire/livewire.csp.min.js.map', 'up');
    }
}
