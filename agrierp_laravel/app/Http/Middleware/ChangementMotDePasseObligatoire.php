<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Ticket MDP-1 — tant que `users.must_change_password` est vrai (mot de passe TEMPORAIRE posé par un administrateur),
 * AUCUNE requête web n'aboutit sauf la page dédiée de changement de mot de passe.
 *
 *  - page (GET et autres) : redirection vers `mot-de-passe.obligatoire` ;
 *  - requête JavaScript / JSON : **403** `{changement_mot_de_passe_obligatoire: true}` ;
 *  - envoi Livewire (`POST /livewire/update`) : accepté SEULEMENT si tous ses composants sont celui de la page dédiée
 *    (le nom du composant est lu dans le `snapshot` signé) — exempter la route en bloc laisserait n'importe quel
 *    composant de l'application répondre à un compte qui n'a pas encore choisi son mot de passe.
 *
 * Exempts : la page dédiée, la déconnexion, le verrou de session (état propre, vu par `SessionVerrouillee` qui passe
 * AVANT dans le groupe `web`), les pages publiques, la sonde `/up`, les fichiers JavaScript de Livewire. Un visiteur
 * non connecté n'est jamais concerné. L'API du poste a son propre garde (`ChangementMotDePasseObligatoireApi`).
 *
 * ⚠️ Dans le groupe `web` et nulle part ailleurs (`bootstrap/app.php`) : `ChangementMotDePasseObligatoireTest` le garde.
 */
class ChangementMotDePasseObligatoire
{
    /** Composant Livewire de la page dédiée (nom d'alias du `snapshot`). */
    public const COMPOSANT = 'auth.changement-mot-de-passe-obligatoire';

    private const ROUTES_EXEMPTES = [
        'mot-de-passe.obligatoire',
        'logout',
        'login',
        'session.verrou',
        'session.deverrouiller',
        'session.verrouiller',
        'public.welcome',
        'public.presentation',
        'health-check',
    ];

    public function handle(Request $request, Closure $next): Response
    {
        $utilisateur = $request->user();

        if (! $utilisateur || ! $utilisateur->must_change_password) {
            return $next($request);
        }

        if ($request->headers->has('X-Livewire')) {
            if ($this->envoiDeLaPageDediee($request)) {
                return $next($request);
            }

            return $this->refuserEnJson();
        }

        if ($this->estExempte($request)) {
            return $next($request);
        }

        if ($request->expectsJson() || $request->ajax()) {
            return $this->refuserEnJson();
        }

        return redirect()->route('mot-de-passe.obligatoire');
    }

    private function refuserEnJson(): Response
    {
        return response()->json([
            'message' => 'Vous devez changer votre mot de passe temporaire avant de continuer.',
            'changement_mot_de_passe_obligatoire' => true,
            'url' => route('mot-de-passe.obligatoire'),
        ], 403);
    }

    private function estExempte(Request $request): bool
    {
        $nom = $request->route()?->getName();
        if ($nom !== null && in_array($nom, self::ROUTES_EXEMPTES, true)) {
            return true;
        }

        return $request->is('livewire/livewire.js', 'livewire/livewire.min.js.map', 'livewire/livewire.csp.min.js', 'livewire/livewire.csp.min.js.map', 'up');
    }

    /** Vrai si l'envoi Livewire ne porte QUE des composants de la page dédiée. */
    private function envoiDeLaPageDediee(Request $request): bool
    {
        $composants = $request->input('components');
        if (! is_array($composants) || $composants === []) {
            return false;
        }

        foreach ($composants as $composant) {
            $snapshot = is_array($composant) ? ($composant['snapshot'] ?? null) : null;
            $donnees = is_string($snapshot) ? json_decode($snapshot, true) : null;
            if (($donnees['memo']['name'] ?? null) !== self::COMPOSANT) {
                return false;
            }
        }

        return true;
    }
}
