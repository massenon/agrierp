<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 15.54 — VIDER LES SESSIONS (décision client du 17/10/2026).
 *
 * Déconnecte TOUT LE MONDE d'un geste : les sessions web (table `sessions`, pilote `database`) et les jetons
 * Sanctum des postes Windows (`personal_access_tokens`). Chaque poste devra se reconnecter ; ses saisies en
 * attente restent sur la machine (`sync_status = pending`) et partent après la reconnexion.
 *
 * ⚠️ La session de celui qui lance l'opération est CONSERVÉE (`$sessionAConserver`) : vider la sienne le
 * renverrait à l'écran de connexion au milieu de l'action, sans le compte rendu.
 */
class ViderSessionsService
{
    /** @return array{sessions: int, jetons: int} */
    public function vider(?string $sessionAConserver = null): array
    {
        $sessions = 0;
        if (Schema::hasTable('sessions')) {
            $sessions = DB::table('sessions')
                ->when($sessionAConserver, fn ($q) => $q->where('id', '!=', $sessionAConserver))
                ->delete();
        }

        $jetons = Schema::hasTable('personal_access_tokens')
            ? DB::table('personal_access_tokens')->delete()
            : 0;

        return ['sessions' => $sessions, 'jetons' => $jetons];
    }
}
