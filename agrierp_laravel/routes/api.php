<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\AnimalController;
use App\Http\Controllers\Api\AttestationController;
use App\Http\Controllers\Api\ContactController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\ReinitialisationDonneesController;
use App\Http\Controllers\Api\SupervisionSynchronisationController;
use App\Http\Controllers\Api\SyncController;
use App\Http\Controllers\Api\VenteController;
use Illuminate\Support\Facades\Route;

/**
 * GAP CRITIQUE COMBLÉ — ce fichier n'existait pas du tout avant ce
 * ticket, malgré `LARAVEL_SYNC_FLUTTER.md` documentant les 3 endpoints
 * ci-dessous depuis longtemps. Confirmé absent lors de l'audit
 * "Communication Flutter ↔ Laravel" (question directe de l'utilisateur).
 *
 * Laravel 11 charge ce fichier automatiquement avec le préfixe `/api` et
 * le middleware group `api` — aucune modification de `bootstrap/app.php`
 * nécessaire (skeleton standard, déjà présent localement).
 */

// ⚠️⚠️ TICKET 14.64 — LIMITEUR DE DEBIT SUR LA CONNEXION. Cette route
// acceptait un nombre illimite de tentatives : une API Sanctum sans
// `throttle` est ouverte au bourrage de mots de passe, et c'est la seule
// porte d'entree du poste Flutter. 5 tentatives par minute et par IP
// laissent passer un caissier qui se trompe, pas un automate.
Route::post('/auth/login', [AuthController::class, 'login'])
    ->middleware('throttle:5,1');

// Ticket S3 — `CompteActif` : un compte désactivé sur le web perd aussitôt l'accès de ses postes.
Route::middleware(['auth:sanctum', \App\Http\Middleware\CompteActif::class])->group(function () {
    Route::post('/auth/logout', [AuthController::class, 'logout']);
    // Ticket 15.9 : changement de mot de passe depuis le poste. Même limiteur
    // que la connexion : il vérifie lui aussi un mot de passe.
    Route::post('/auth/password', [AuthController::class, 'changePassword'])
        ->middleware('throttle:5,1');
    Route::get('/auth/me', [AuthController::class, 'me']);

    // Ticket 15.14 : export PDF de la fiche d'un sujet depuis le poste.
    Route::get('/animals/{id}/pdf', [AnimalController::class, 'pdf'])
        ->middleware('throttle:30,1');

    // Ticket 15.13 : attestations depuis le poste — génération (PDF) et modèles.
    // Ticket AV2 — ticket PDF d'une vente (« Télécharger PDF » du détail, Historique des Ventes).
    Route::get('/ventes/{id}/pdf', [VenteController::class, 'pdf'])
        ->middleware('throttle:30,1');

    Route::post('/attestations', [AttestationController::class, 'generer'])
        ->middleware('throttle:30,1');
    Route::put('/attestation-templates/{type}', [AttestationController::class, 'enregistrerModele']);

    // Ticket 15.11 : « Contactez l'Éditeur » depuis le poste. Limité : chaque
    // appel envoie un e-mail réel.
    Route::post('/contact', [ContactController::class, 'store'])
        ->middleware('throttle:5,1');

    // Ticket 15.10 : actions sur les notifications depuis le poste.
    Route::post('/notifications/{id}/read', [NotificationController::class, 'markAsRead']);
    Route::delete('/notifications/{id}', [NotificationController::class, 'destroy']);

    // Ticket S1 — débit borné : un poste synchronise toutes les quelques minutes ; 30 appels par minute et par
    // compte laissent la marge d'une relance manuelle répétée sans permettre d'épuiser le serveur.
    // Ticket S-T4 — le tirage est PAGINÉ : un poste resté longtemps hors ligne fait une requête par page. Sous le
    // compteur commun (30 / min, partagé avec l'envoi), son tirage tomberait en 429 au milieu, repartirait de la
    // page 1 et ne finirait jamais. Compteur PROPRE, à 120 pages par minute (120 000 lignes au plus).
    Route::get('/sync/pull', [SyncController::class, 'pull'])->middleware('throttle:120,1,sync-pull');
    Route::post('/sync/push', [SyncController::class, 'push'])->middleware('throttle:30,1');

    // Ticket S-T6 — demande de synchronisation déposée au web, lue par chaque poste toutes les 30 s ; comptes du
    // serveur pour le contrôle de cohérence. Compteurs de débit PROPRES (3e paramètre) : sans préfixe, tous les
    // `throttle:N,1` d'un compte partagent la même clé, et l'interrogation régulière mangerait le crédit du tirage.
    Route::get('/sync/demande', [SupervisionSynchronisationController::class, 'demande'])
        ->middleware('throttle:6,1,sync-demande');
    // Ticket SW-1 — le poste acquitte une resynchronisation demandée par le web (drapeau « Renvoyer vers ce poste »).
    Route::post('/sync/resynchronisation/acquittement', [SupervisionSynchronisationController::class, 'acquitterResynchronisation'])
        ->middleware('throttle:6,1,sync-resync-acquittement');
    Route::get('/sync/coherence', [SupervisionSynchronisationController::class, 'coherence'])
        ->middleware('throttle:10,1,sync-coherence');

    // Ticket R-1 — « Réinitialisation des données » depuis le poste : même droit (`manage-parametres`, vérifié par
    // le contrôleur), mêmes verrous et même service que l'onglet web. Compteur de débit propre.
    Route::get('/parametres/reinitialisation', [ReinitialisationDonneesController::class, 'etat'])
        ->middleware('throttle:30,1,reinitialisation');
    Route::post('/parametres/reinitialisation/mode-demo', [ReinitialisationDonneesController::class, 'basculerModeDemo'])
        ->middleware('throttle:10,1,reinitialisation-bascule');
    Route::post('/parametres/reinitialisation', [ReinitialisationDonneesController::class, 'reinitialiser'])
        ->middleware('throttle:5,1,reinitialisation-execution');
});
