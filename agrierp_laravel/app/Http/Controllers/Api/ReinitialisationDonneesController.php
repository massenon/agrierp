<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CompanySetting;
use App\Services\ReinitialisationDonneesService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Laravel\Sanctum\PersonalAccessToken;

/**
 * Ticket R-1 (demande du client : « sur le web et le poste ») — « RÉINITIALISATION DES DONNÉES » DEPUIS LE POSTE.
 *
 * ⚠️⚠️ EXACTEMENT L'ACTION DE L'ÉCRAN WEB (`Livewire\Parametres\ReinitialisationDonnees`), jamais une variante :
 *  - même droit, vérifié sur chaque route : `manage-parametres` (le `authorize()` du composant) ; refus 403 en
 *    français pour tout autre rôle ;
 *  - mêmes verrous, dans le même ordre : mode démonstration activé (sinon 409, message du web), puis le mot
 *    « REINITIALISER » recopié (sinon 422, message du web sous le champ `confirmation`) ;
 *  - même service (`ReinitialisationDonneesService::executer()`), donc même vidage, même marque `data_reset_at`,
 *    même journal (`donnees.reinitialisees`, et `demo_mode.enabled` / `demo_mode.disabled` pour la bascule) ;
 *  - mêmes messages (ceux du service, que le composant web lit aussi).
 *
 * ⚠️ Le JETON du poste qui lance l'opération est conservé — comme la session de l'administrateur au web : le
 * poste purge ses données et tire aussitôt avec lui. Tous les autres jetons et sessions sont vidés (15.54).
 */
class ReinitialisationDonneesController extends Controller
{
    public const REFUS_ROLE = 'Votre rôle ne permet pas de réinitialiser les données.';

    /** GET /api/parametres/reinitialisation — état de la bascule, pour l'onglet du poste. */
    public function etat(Request $request): JsonResponse
    {
        $this->autoriser($request);

        return response()->json([
            'mode_demo_actif' => ReinitialisationDonneesService::modeDemoActif(),
            'mot_de_confirmation' => ReinitialisationDonneesService::MOT_DE_CONFIRMATION,
        ]);
    }

    /** POST /api/parametres/reinitialisation/mode-demo — le bouton « Activé / Désactivé » du web. */
    public function basculerModeDemo(Request $request): JsonResponse
    {
        $this->autoriser($request);

        $actif = ReinitialisationDonneesService::basculerModeDemo();

        if ($actif === null) {
            return response()->json([
                'message' => 'Réglages de l\'entreprise absents : le mode démonstration ne peut pas être basculé.',
            ], 409);
        }

        return response()->json([
            'mode_demo_actif' => $actif,
            'message' => ReinitialisationDonneesService::messageBascule($actif),
            'type' => $actif ? 'warning' : 'success',
        ]);
    }

    /** POST /api/parametres/reinitialisation — « Confirmer la réinitialisation », champ `confirmation`. */
    public function reinitialiser(Request $request, ReinitialisationDonneesService $service): JsonResponse
    {
        $this->autoriser($request);

        if (! ReinitialisationDonneesService::modeDemoActif()) {
            return response()->json(['message' => ReinitialisationDonneesService::REFUS_MODE_DEMO], 409);
        }

        if ($request->input('confirmation') !== ReinitialisationDonneesService::MOT_DE_CONFIRMATION) {
            $message = ReinitialisationDonneesService::messageConfirmation();

            return response()->json([
                'message' => $message,
                'errors' => ['confirmation' => [$message]],
            ], 422);
        }

        $jeton = $request->user()->currentAccessToken();
        $supprimees = $service->executer($jeton instanceof PersonalAccessToken ? $jeton->getKey() : null);
        $total = array_sum($supprimees);

        return response()->json([
            'message' => ReinitialisationDonneesService::messageResultat($total),
            'total' => $total,
            'supprimees' => $supprimees,
            // ⚠️ Même forme que la clé `data_reset_at` du tirage (`SyncController`) : le poste la compare telle
            // quelle à celle qu'il a notée, et ne purge pas une seconde fois au tirage qui suit.
            'data_reset_at' => CompanySetting::query()->first()?->data_reset_at?->toIso8601String(),
        ]);
    }

    private function autoriser(Request $request): void
    {
        abort_unless($request->user()?->can('manage-parametres'), 403, self::REFUS_ROLE);
    }
}
