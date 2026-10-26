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
    })->create();
