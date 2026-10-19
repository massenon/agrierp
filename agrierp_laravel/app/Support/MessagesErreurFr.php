<?php

namespace App\Support;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;
use Throwable;

/**
 * Ticket U5 (D-U5) — « TOUS LES MESSAGES D'ERREUR EN FRANÇAIS », AU-DELÀ DE LA VALIDATION.
 *
 * Deux trous restaient une fois `lang/fr` en place :
 *
 * 1. Les réponses JSON d'erreur du framework (API du poste) portent le message BRUT de
 *    l'exception, jamais traduit : « Unauthenticated. », « This action is unauthorized. »,
 *    « Too Many Attempts. », « No query results for model [App\Models\Sale] … ».
 *    `traduireJson()` les fait passer par `lang/fr.json` ; un 404/405 dont le motif est technique
 *    reçoit une phrase française générique. ⚠️ La FORME de la réponse (`message`, `errors`, code
 *    HTTP) ne change pas : seul le texte de `message` est traduit.
 *
 * 2. Quelques écrans attrapent `\Throwable` et affichent `$e->getMessage()` en toast. Une
 *    exception levée par NOTRE code (`app/`) porte une phrase française écrite pour l'utilisateur
 *    (« Cette écriture est verrouillée… ») ; une exception du framework ou d'un paquet
 *    (`QueryException`, erreur PDO…) porte un détail technique anglais. `pourUtilisateur()` garde
 *    la première, et remplace la seconde par une phrase française — le détail va au journal.
 */
class MessagesErreurFr
{
    public const GENERIQUE = 'Une erreur inattendue est survenue. Réessayez ; si le problème persiste, '
        .'contactez l\'administrateur (le détail technique est consigné dans le journal du serveur).';

    /** Traduit le `message` d'une réponse JSON d'erreur, sans toucher à sa forme. */
    public static function traduireJson(Response $reponse): Response
    {
        if (! $reponse instanceof JsonResponse) {
            return $reponse;
        }

        $donnees = $reponse->getData(true);

        if (! is_array($donnees) || ! isset($donnees['message']) || ! is_string($donnees['message'])) {
            return $reponse;
        }

        $message = $donnees['message'];
        $traduit = __($message);

        if ($traduit === $message) {
            $traduit = match (true) {
                $reponse->getStatusCode() === 404 && self::estTechnique($message) => 'Ressource introuvable.',
                $reponse->getStatusCode() === 405 && self::estTechnique($message) => 'Méthode non autorisée pour cette adresse.',
                default => $message,
            };
        }

        if ($traduit !== $message) {
            $donnees['message'] = $traduit;
            $reponse->setData($donnees);
        }

        return $reponse;
    }

    /**
     * Message d'une exception attrapée, pour un toast ou un motif de refus : le texte de l'exception
     * s'il vient de notre code, une phrase française générique sinon (et le détail au journal).
     */
    public static function pourUtilisateur(Throwable $e): string
    {
        if (self::vientDeLApplication($e) && $e->getMessage() !== '') {
            return $e->getMessage();
        }

        Log::error('Erreur inattendue affichée sous un message générique', [
            'exception' => $e::class,
            'message' => $e->getMessage(),
            'fichier' => $e->getFile().':'.$e->getLine(),
        ]);

        return self::GENERIQUE;
    }

    /** Levée par un fichier de `app/` (et non du framework ou d'un paquet de `vendor/`). */
    private static function vientDeLApplication(Throwable $e): bool
    {
        return str_starts_with(realpath($e->getFile()) ?: $e->getFile(), realpath(app_path()) ?: app_path());
    }

    /** Motif technique d'un 404/405 du framework (route ou modèle introuvable). */
    private static function estTechnique(string $message): bool
    {
        return $message === ''
            || str_starts_with($message, 'No query results for model')
            || str_starts_with($message, 'The route ')
            || str_contains($message, 'method is not supported');
    }
}
