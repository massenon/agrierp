<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\DemandeSynchronisation;
use App\Models\DemandeSynchronisationServie;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Ticket S-T6 — « DEMANDER LA SYNCHRONISATION DES POSTES » (méthode TATACORA, bouton du serveur).
 *
 * Le serveur ne joint pas les postes : il dépose une demande ; chaque poste connecté interroge
 * `GET /api/sync/demande` toutes les 30 s et, s'il y trouve une demande qui ne lui a pas encore été servie, lance une
 * synchronisation (tirage puis envoi). La lecture MARQUE la demande servie pour ce poste : elle ne déclenche qu'une
 * synchronisation par poste.
 *
 * ⚠️ UNE DEMANDE EXPIRE APRÈS [VALIDITE_MINUTES]. Elle dit « synchronisez maintenant » : un poste éteint qui ne la lit
 * que le lendemain se synchronise de toute façon à son démarrage (S-T3) ; la lui servir encore ne ferait qu'ajouter
 * une synchronisation sans objet.
 */
class DemandeSynchronisationService
{
    public const VALIDITE_MINUTES = 60;

    /** Dépose une demande pour un poste (`$poste` = nom de son jeton) ou pour tous (`null`), et l'audite. */
    public function demander(?string $poste, ?User $par = null): DemandeSynchronisation
    {
        $demande = DemandeSynchronisation::create([
            'poste' => $poste,
            'demandee_le' => now(),
            'demandee_par' => $par?->id,
        ]);

        AuditLog::record($poste === null ? 'sync.demande_tous' : 'sync.demande_poste', 'sync', $par?->id);

        return $demande;
    }

    /**
     * Demandes encore valides, adressées à ce poste ou à tous, qu'il n'a pas encore lues — marquées servies dans la
     * même transaction. Rend la plus récente, ou `null` s'il n'y en a aucune.
     */
    public function servir(string $poste, ?Carbon $maintenant = null): ?DemandeSynchronisation
    {
        $maintenant ??= now();

        return DB::transaction(function () use ($poste, $maintenant) {
            $dues = DemandeSynchronisation::query()
                ->with('auteur:id,name')
                ->where('demandee_le', '>=', $maintenant->copy()->subMinutes(self::VALIDITE_MINUTES))
                ->where(fn ($q) => $q->whereNull('poste')->orWhere('poste', $poste))
                ->whereDoesntHave('servies', fn ($q) => $q->where('poste', $poste))
                ->orderByDesc('demandee_le')
                ->lockForUpdate()
                ->get();

            foreach ($dues as $demande) {
                // `insertOrIgnore` : deux lectures simultanées du même poste ne servent la demande qu'une fois.
                DemandeSynchronisationServie::query()->insertOrIgnore([
                    'id' => (string) \Illuminate\Support\Str::uuid(),
                    'demande_id' => $demande->id,
                    'poste' => $poste,
                    'servie_le' => $maintenant,
                ]);
            }

            return $dues->first();
        });
    }
}
