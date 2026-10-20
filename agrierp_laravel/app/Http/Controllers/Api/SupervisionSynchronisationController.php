<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ControleCoherence;
use App\Services\CoherenceSynchronisationService;
use App\Services\FinancialReportService;
use App\Services\DemandeSynchronisationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/**
 * Ticket S-T6 — SUPERVISION DE LA SYNCHRONISATION PAR LE SERVEUR (méthode TATACORA, § 3) : demande de synchronisation
 * lue par les postes, et comptes du serveur pour le contrôle de cohérence.
 *
 * ⚠️ Contrôleur à part de `SyncController` : ces deux points d'entrée ne lisent ni n'écrivent aucune donnée métier
 * synchronisée ; le protocole `/api/sync/pull` + `/api/sync/push` reste tel quel (décision D-SYNC-1).
 *
 * Le poste est identifié par le NOM DE SON JETON Sanctum (`AuthController` le crée sous `device_name`), comme dans le
 * journal de synchronisation (H3).
 */
class SupervisionSynchronisationController extends Controller
{
    /**
     * GET /api/sync/demande — `{"demande": true, "demandee_le": …, "demandee_par": …}` si une demande valide n'a pas
     * encore été servie à ce poste (elle l'est alors), `{"demande": false}` sinon.
     */
    public function demande(Request $request, DemandeSynchronisationService $demandes): JsonResponse
    {
        $poste = $request->user()?->currentAccessToken()?->name;
        if (! is_string($poste) || $poste === '') {
            return response()->json(['demande' => false]);
        }

        $demande = $demandes->servir($poste);

        return response()->json($demande === null
            ? ['demande' => false]
            : [
                'demande' => true,
                'demandee_le' => $demande->demandee_le?->toIso8601String(),
                'demandee_par' => $demande->auteur?->name,
            ]);
    }

    /**
     * GET /api/sync/coherence?depuis=AAAA-MM-JJ — nombre de lignes et total par table et par jour
     * (`CoherenceSynchronisationService::AGREGATS`).
     */
    public function coherence(Request $request, CoherenceSynchronisationService $coherence): JsonResponse
    {
        $request->validate([
            'depuis' => [
                'required', 'date_format:Y-m-d',
                'after_or_equal:'.now()->subDays(CoherenceSynchronisationService::JOURS_MAXIMUM)->toDateString(),
            ],
        ]);

        $depuis = Carbon::createFromFormat('Y-m-d', $request->string('depuis')->toString())->startOfDay();

        $reponse = [
            'server_time' => now()->toIso8601String(),
            'depuis' => $depuis->toDateString(),
            'tables' => $coherence->calculer($depuis),
            // Ticket EX1 — invariant comptable « ouverture de N+1 = clôture de N » (classes 1 à 5), vu du serveur.
            // Servi aux seuls comptes qui lisent la comptabilité (ceux à qui le journal descend) ; `null` sinon.
            'anouveaux' => $request->user()?->can('view-comptabilite')
                ? app(FinancialReportService::class)->controleAnouveaux()
                : null,
        ];

        // La modale « Synchronisation » du web montre le dernier contrôle de chaque poste. Un échec de cette note ne
        // fait jamais échouer le contrôle.
        try {
            ControleCoherence::create([
                'user_id' => $request->user()?->id,
                'poste' => $request->user()?->currentAccessToken()?->name ?? '—',
                'depuis' => $depuis->toDateString(),
            ]);
        } catch (\Throwable $e) {
            report($e);
        }

        return response()->json($reponse);
    }
}
