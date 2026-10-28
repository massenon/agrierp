<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Services\DemandeSynchronisationService;
use App\Services\ImportModuleService;
use App\Services\JournalSynchronisationService;
use App\Services\SauvegardeService;
use App\Services\SmsService;
use App\Services\ViderSessionsService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Laravel\Sanctum\PersonalAccessToken;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

/**
 * Tickets PA-1, PA-5, PA-6, PA-8 (test SMS) — GESTES D'ADMINISTRATION EN LIGNE, depuis le poste.
 *
 * Ces gestes agissent sur le SERVEUR (fermer des sessions, révoquer un appairage, générer ou lire une sauvegarde, appeler le
 * fournisseur SMS) : ils n'ont pas de version hors ligne. Mêmes services, mêmes droits (`manage-users` / `manage-parametres`)
 * et mêmes traces d'audit que les composants web correspondants. Précédent : `ReinitialisationDonneesController` (R-1).
 */
class AdministrationEnLigneController extends Controller
{
    private function exiger(Request $request, string $droit, string $refus): ?JsonResponse
    {
        return $request->user()?->can($droit) ? null : response()->json(['message' => $refus], 403);
    }

    // ── PA-1 · Déconnecter toutes les sessions ───────────────────────────────

    public function viderSessions(Request $request): JsonResponse
    {
        if ($r = $this->exiger($request, 'manage-users', 'Votre rôle ne permet pas de fermer les sessions.')) {
            return $r;
        }

        // Le jeton de CE poste est conservé : l'administrateur qui agit ne se déconnecte pas lui-même.
        $resultat = app(ViderSessionsService::class)->vider(null, $request->user()->currentAccessToken()?->getKey());
        AuditLog::record('sessions.videes', 'administration');

        return response()->json($resultat + ['message' => "{$resultat['sessions']} session(s) web fermée(s), {$resultat['jetons']} poste(s) déconnecté(s). Votre session est conservée."]);
    }

    // ── PA-5 · Postes appairés ───────────────────────────────────────────────

    public function postes(Request $request): JsonResponse
    {
        if ($r = $this->exiger($request, 'manage-users', 'Votre rôle ne permet pas de voir les postes.')) {
            return $r;
        }

        return response()->json(['postes' => app(JournalSynchronisationService::class)->etatDesPostes()->map(fn (array $l) => [
            'poste' => $l['poste'],
            'utilisateur' => $l['utilisateur'],
            'dernier_contact' => $l['dernier_contact']?->toIso8601String(),
            'dernier_envoi' => $l['dernier_envoi']?->toIso8601String(),
            'etat' => $l['etat'],
            'libelle_etat' => $l['libelle_etat'],
            'acceptes' => $l['acceptes'],
            'refuses' => $l['refuses'],
        ])->values()]);
    }

    public function demanderSynchronisation(Request $request): JsonResponse
    {
        if ($r = $this->exiger($request, 'manage-users', 'Votre rôle ne permet pas de demander une synchronisation.')) {
            return $r;
        }

        $poste = $request->input('poste');

        if ($poste !== null && ! $this->posteConnu((string) $poste)) {
            return response()->json(['message' => 'Poste inconnu du serveur : demande non envoyée.'], 422);
        }

        app(DemandeSynchronisationService::class)->demander($poste, $request->user());

        return response()->json(['message' => $poste === null
            ? 'Demande envoyée : les postes connectés synchroniseront dans les 30 secondes.'
            : "Demande envoyée au poste {$poste} : il synchronisera dans les 30 secondes s'il est connecté."]);
    }

    public function revoquerAppairage(Request $request): JsonResponse
    {
        if ($r = $this->exiger($request, 'manage-users', 'Votre rôle ne permet pas de révoquer un appairage.')) {
            return $r;
        }

        $poste = (string) $request->input('poste');

        if (! $this->posteConnu($poste)) {
            return response()->json(['message' => 'Poste inconnu du serveur : aucun appairage révoqué.'], 422);
        }

        $supprimes = PersonalAccessToken::query()->where('name', $poste)->delete();
        AuditLog::record('sync.appairage_revoque', 'sync');

        return response()->json(['message' => "Appairage du poste {$poste} révoqué ({$supprimes} jeton".($supprimes > 1 ? 's' : '').' supprimé'.($supprimes > 1 ? 's' : '')
            .") : il ne synchronisera plus jusqu'à une nouvelle connexion."]);
    }

    private function posteConnu(string $poste): bool
    {
        return app(JournalSynchronisationService::class)->etatDesPostes()->contains(fn (array $l) => $l['poste'] === $poste);
    }

    // ── PA-6 · Sauvegardes ───────────────────────────────────────────────────

    public function sauvegardes(Request $request): JsonResponse
    {
        if ($r = $this->exiger($request, 'manage-parametres', 'Votre rôle ne permet pas de gérer les sauvegardes.')) {
            return $r;
        }

        return response()->json([
            'fichiers' => collect(app(SauvegardeService::class)->lister())->map(fn (array $f) => [
                'fichier' => $f['fichier'], 'date' => $f['date']->toIso8601String(), 'portee' => $f['portee'], 'taille' => $f['taille'],
            ])->values(),
            'modules' => collect(SauvegardeService::modules())->map(fn (array $m) => $m['libelle']),
        ]);
    }

    public function genererSauvegarde(Request $request): JsonResponse
    {
        if ($r = $this->exiger($request, 'manage-parametres', 'Votre rôle ne permet pas de gérer les sauvegardes.')) {
            return $r;
        }

        $module = (string) $request->input('module', '');

        if ($module === '') {
            $resultat = app(SauvegardeService::class)->genererComplete();
            AuditLog::record('database.backup_generated', 'parametres');

            return response()->json([
                'type' => $resultat['moteur'] === 'mysqldump' ? 'success' : 'warning',
                'message' => $resultat['moteur'] === 'mysqldump'
                    ? 'Sauvegarde complète générée : '.$resultat['fichier']
                    : 'mysqldump indisponible sur ce serveur — export des DONNÉES seules généré ('.$resultat['fichier'].'). Ce fichier ne contient pas le schéma.',
            ]);
        }

        $fichier = app(SauvegardeService::class)->genererModule($module);

        if ($fichier === null) {
            return response()->json(['message' => 'Module inconnu.'], 422);
        }

        AuditLog::record('database.backup_module_generated', 'parametres');

        return response()->json(['type' => 'success', 'message' => 'Export généré : '.$fichier]);
    }

    public function telechargerSauvegarde(Request $request, string $fichier): BinaryFileResponse|JsonResponse
    {
        if ($r = $this->exiger($request, 'manage-parametres', 'Votre rôle ne permet pas de gérer les sauvegardes.')) {
            return $r;
        }

        $chemin = app(SauvegardeService::class)->chemin(basename($fichier));

        if ($chemin === null) {
            return response()->json(['message' => 'Sauvegarde introuvable.'], 404);
        }

        AuditLog::record('database.backup_downloaded', 'parametres');

        return response()->download($chemin);
    }

    public function importerModule(Request $request): JsonResponse
    {
        if ($r = $this->exiger($request, 'manage-parametres', 'Votre rôle ne permet pas de gérer les sauvegardes.')) {
            return $r;
        }

        $fichier = (string) $request->input('fichier', '');
        $module = (string) $request->input('module', '');

        if ($fichier === '' || $module === '') {
            return response()->json(['message' => 'Choisissez un fichier et un module.'], 422);
        }

        $chemin = app(SauvegardeService::class)->chemin(basename($fichier));

        if ($chemin === null) {
            return response()->json(['message' => 'Sauvegarde introuvable.'], 404);
        }

        $resultat = app(ImportModuleService::class)->importer(file_get_contents($chemin), $module);

        return response()->json([
            'type' => $resultat['rejetees'] > 0 ? 'warning' : 'success',
            'message' => $resultat['rejetees'] > 0
                ? "{$resultat['inserees']} ligne(s) importée(s), {$resultat['rejetees']} instruction(s) refusée(s) — ".implode(' · ', $resultat['motifs'])
                : "{$resultat['inserees']} ligne(s) importée(s).",
        ]);
    }

    // ── PA-8 · SMS de test ───────────────────────────────────────────────────

    public function testerSms(Request $request): JsonResponse
    {
        if ($r = $this->exiger($request, 'manage-parametres', 'Votre rôle ne permet pas de tester les SMS.')) {
            return $r;
        }

        $destinataire = trim((string) $request->input('destinataire', ''));

        if ($destinataire === '') {
            return response()->json(['message' => 'Le champ destinataire est obligatoire.'], 422);
        }

        $resultat = app(SmsService::class)->send($destinataire, 'Ceci est un SMS de test envoyé depuis AgriERP.');

        return response()->json(['type' => $resultat['success'] ? 'success' : 'error', 'message' => $resultat['message']]);
    }
}
