<?php

use App\Support\MessagesErreurFr;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Symfony\Component\HttpFoundation\Response;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Sprint VW : le verrou de session s'applique à TOUTE requête web (pages, `/livewire/update`, envois de
        // fichiers). Dans le groupe `web` et nulle part ailleurs : l'API du poste (jetons Sanctum) n'a pas de session.
        $middleware->web(append: [
            \App\Http\Middleware\SessionVerrouillee::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // Ticket U5 (D-U5) : le `message` des réponses JSON d'erreur (API du poste) en français
        // (« Unauthenticated. » → « Session expirée… »). La forme de la réponse ne change pas.
        $exceptions->respond(fn (Response $reponse) => MessagesErreurFr::traduireJson($reponse));

        // « 419 Page expirée » en cliquant sur Déconnexion : la page est restée ouverte plus longtemps que la session,
        // son jeton CSRF n'existe plus. Se déconnecter n'a jamais besoin de ce jeton pour aboutir (la session est
        // déjà perdue ou sur le point de l'être) : on termine la déconnexion et on renvoie vers la connexion, sans
        // page d'erreur. Tout autre envoi expiré garde la page 419 habituelle.
        $exceptions->render(function (\Symfony\Component\HttpKernel\Exception\HttpException $e, \Illuminate\Http\Request $request) {
            // Le gestionnaire a déjà converti TokenMismatchException en HttpException 419.
            if ($e->getStatusCode() !== 419 || ! $request->isMethod('POST') || ! $request->is('logout')) {
                return null;
            }

            \Illuminate\Support\Facades\Auth::guard('web')->logout();
            if ($request->hasSession()) {
                $request->session()->invalidate();
                $request->session()->regenerateToken();
                $request->session()->flash('toast', [
                    'message' => 'Votre session avait expiré : vous êtes déconnecté.',
                    'type' => 'success',
                ]);
            }

            return redirect()->route('login');
        });
    })->create();
