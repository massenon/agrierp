<?php

namespace App\Actions;

use App\Models\AuditLog;
use App\Models\LivestockLot;
use App\Services\AccountingEntryService;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Ticket BS1 — POINT DE PASSAGE UNIQUE d'une bande : création, modification, archivage.
 *
 * Ces trois gestes vivaient dans `Livewire\Elevage\GestionBandes`. Le poste crée, modifie et archive désormais ses
 * bandes (hors ligne, rejouées à l'envoi par `SyncController::pushLots`) : les deux chemins passent ici, avec les
 * mêmes règles, les mêmes effets (audit compris) et les mêmes messages.
 *
 * Règles :
 *  - création : effectif initial = effectif courant = quantité saisie, statut `actif`, `is_active`. 🔴→✅ Une bande
 *    datée dans un exercice CLOS est refusée (décision Q3 du 20/10/2026 étendue à la bande : sa quantité initiale est
 *    le départ de toutes ses fiches) — motif R4, sous « Date de Création ». La bande d'origine (constitution) reste du
 *    ressort du transfert (`TransferBetweenLotsAction`), jamais d'ici : le poste l'envoie comme un transfert à part ;
 *  - modification : stade, statut, et effectif actuel SEULEMENT s'il est fourni (correction explicite de
 *    l'exploitant, comme « Modifier la Bande » du web). Le code, l'espèce, l'effectif initial ne changent jamais.
 *    Une bande ARCHIVÉE n'est plus modifiable ; une modification identique n'écrit rien (idempotence des renvois) ;
 *  - archivage : `is_active = false`, la ligne est gardée. Un second archivage n'a aucun effet, ni trace.
 *
 * ⚠️ LA CASCADE DES EFFECTIFS N'EST PAS CONTOURNÉE ICI : la création ne pose aucune fiche, et la correction d'effectif
 * est celle que le web offre déjà (la prochaine fiche réécrit l'effectif de la bande par `recalculerEnCascade`).
 */
class SaisieBandeAction
{
    public const MESSAGE_ARCHIVEE = 'Cette bande est archivée : elle ne peut plus être modifiée.';

    public const ARCHIVEE = 'archivee';

    /** Sortie de [archiver] : la bande l'était déjà, rien n'est écrit. */
    public const DEJA_ARCHIVEE = 'deja_archivee';

    /** Sortie de [archiver] : la bande vient d'être archivée. */
    public const ARCHIVEE_MAINTENANT = 'archivee_maintenant';

    /**
     * @param  array{code: string, species_id: string, stage: string, created_date: string, quantity: int|string,
     *               acquisition_cost?: int|float|string|null, product_id?: ?string}  $donnees
     *
     * @throws ValidationException  exercice clos couvrant la date de création
     */
    public function creer(array $donnees, ?string $id = null): LivestockLot
    {
        $date = substr((string) $donnees['created_date'], 0, 10);

        if ($refus = app(AccountingEntryService::class)->refusExerciceClos($date)) {
            throw ValidationException::withMessages(['created_date' => $refus]);
        }

        return DB::transaction(function () use ($donnees, $id, $date) {
            $lot = new LivestockLot();
            if ($id !== null) {
                $lot->id = $id;
            }
            $lot->fill([
                'code' => $donnees['code'],
                'species_id' => $donnees['species_id'],
                // Ticket 14.37 : ce que la bande produit, décidé par l'exploitant.
                'product_id' => ($donnees['product_id'] ?? null) ?: null,
                'stage' => $donnees['stage'],
                'initial_quantity' => (int) $donnees['quantity'],
                'current_quantity' => (int) $donnees['quantity'],
                'created_date' => $date,
                'acquisition_cost' => $donnees['acquisition_cost'] ?? null,
                'status' => 'actif',
                'is_active' => true,
            ]);
            $lot->save();

            AuditLog::record('livestock_lot.created', 'elevage');

            return $lot;
        });
    }

    /**
     * @param  array{stage: string, status: string, current_quantity?: int|string|null}  $donnees
     * @return LivestockLot  la bande, à jour
     *
     * @throws ValidationException  bande archivée
     */
    public function modifier(string $id, array $donnees): LivestockLot
    {
        return DB::transaction(function () use ($id, $donnees) {
            $lot = LivestockLot::lockForUpdate()->findOrFail($id);

            if (! $lot->is_active) {
                throw ValidationException::withMessages(['bande' => self::MESSAGE_ARCHIVEE]);
            }

            $nouveau = ['stage' => $donnees['stage'], 'status' => $donnees['status']];
            if (array_key_exists('current_quantity', $donnees) && $donnees['current_quantity'] !== null) {
                $nouveau['current_quantity'] = (int) $donnees['current_quantity'];
            }

            $lot->fill($nouveau);
            if (! $lot->isDirty()) {
                return $lot;
            }

            $lot->save();
            AuditLog::record('livestock_lot.updated', 'elevage');

            return $lot;
        });
    }

    /** @return string  [ARCHIVEE_MAINTENANT] ou [DEJA_ARCHIVEE] */
    public function archiver(string $id): string
    {
        return DB::transaction(function () use ($id) {
            $lot = LivestockLot::lockForUpdate()->findOrFail($id);

            if (! $lot->is_active) {
                return self::DEJA_ARCHIVEE;
            }

            $lot->update(['is_active' => false]);
            AuditLog::record('livestock_lot.archived', 'elevage');

            return self::ARCHIVEE_MAINTENANT;
        });
    }
}
