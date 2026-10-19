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
 *
 * Ticket R-1 — de même, le jeton du POSTE qui lance une réinitialisation (`$jetonAConserver`) : il purge ses
 * données et tire aussitôt après, avec ce jeton.
 */
class ViderSessionsService
{
    /** @return array{sessions: int, jetons: int} */
    public function vider(?string $sessionAConserver = null, int|string|null $jetonAConserver = null): array
    {
        $sessions = 0;
        if (Schema::hasTable('sessions')) {
            $sessions = DB::table('sessions')
                ->when($sessionAConserver, fn ($q) => $q->where('id', '!=', $sessionAConserver))
                ->delete();
        }

        $jetons = Schema::hasTable('personal_access_tokens')
            ? DB::table('personal_access_tokens')
                ->when($jetonAConserver !== null, fn ($q) => $q->where('id', '!=', $jetonAConserver))
                ->delete()
            : 0;

        return ['sessions' => $sessions, 'jetons' => $jetons];
    }
}
