<?php

namespace App\Actions;

use App\Models\AuditLog;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Rules\UniqueNormalise;
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
 *    l'exploitant, comme « Modifier la Bande » du web). L'espèce et l'effectif initial ne changent jamais ; le code non
 *    plus, SAUF ticket UNI : une bande dont le code est partagé avec une autre se renomme (vers un code libre),
 *    c'est le seul moyen, pour le client, de corriger un doublon déjà présent sans qu'on y touche à sa place.
 *    Une bande ARCHIVÉE n'est plus modifiable ; une modification identique n'écrit rien (idempotence des renvois) ;
 *  - archivage : `is_active = false`, la ligne est gardée. Un second archivage n'a aucun effet, ni trace.
 *    ⚠️ BS-Q3 (décision client du 21/10/2026) : une bande qui a un effectif VIVANT (> 0) ne s'archive pas — il faut
 *    d'abord sortir ou transférer les sujets restants (fiche : mort, vente, don ; transfert vers une autre bande ;
 *    correction d'effectif d'une bande sans fiche). Rien n'est perdu, aucun flux n'est fermé : le vidage existe déjà ;
 *  - BS-Q4 : dès qu'une bande a des fiches journalières, son effectif n'est plus modifiable par « Modifier la
 *    Bande » (la cascade des fiches en est l'UNIQUE écrivain) ; une bande sans fiche garde l'édition libre ;
 *  - BS-Q7 : une bande archivée se RESTAURE (`is_active = true`), sauf si son code est déjà porté par une bande en
 *    cours (jamais deux bandes en cours sous le même code) ;
 *
 * ⚠️ LA CASCADE DES EFFECTIFS N'EST PAS CONTOURNÉE ICI : la création ne pose aucune fiche, et la correction d'effectif
 * est celle que le web offre déjà (la prochaine fiche réécrit l'effectif de la bande par `recalculerEnCascade`).
 */
class SaisieBandeAction
{
    public const MESSAGE_ARCHIVEE = 'Cette bande est archivée : elle ne peut plus être modifiée.';

    /** BS-Q4 : « Modifier la Bande » n'écrit plus l'effectif d'une bande qui a des fiches. */
    public const MESSAGE_EFFECTIF_PAR_LES_FICHES = "L'effectif de cette bande est tenu par ses fiches journalières : corrigez-le depuis la fiche, la bande suit automatiquement.";

    /** Info-bulle du champ « Effectif Actuel » grisé (web et poste). */
    public const INFOBULLE_EFFECTIF_PAR_LES_FICHES = 'Cette bande a des fiches journalières : son effectif se corrige depuis la fiche (la bande suit automatiquement).';

    public const ARCHIVEE = 'archivee';

    /** Sortie de [restaurer] : la bande était déjà en cours, rien n'est écrit. */
    public const DEJA_EN_COURS = 'deja_en_cours';

    /** Sortie de [restaurer] : la bande vient d'être restaurée. */
    public const RESTAUREE_MAINTENANT = 'restauree_maintenant';

    /** BS-Q3 : « Cette bande compte encore 200 sujets vivants : … » (singulier à 1). */
    public static function messageEffectifVivant(int $effectif): string
    {
        return 'Cette bande compte encore '.$effectif.($effectif === 1 ? ' sujet vivant' : ' sujets vivants')
            .' : archivez-la après avoir sorti ou transféré les sujets restants.';
    }

    /** BS-Q7 : le code est pris par une autre bande en cours. */
    public static function messageCodePris(string $code): string
    {
        return 'Le code « '.$code.' » est déjà utilisé par une bande en cours : cette bande ne peut pas être restaurée.';
    }

    /** Une bande a-t-elle au moins une fiche journalière ? (BS-Q4 : alors la cascade tient son effectif.) */
    public static function aDesFiches(string $lotId): bool
    {
        return LivestockDailyEntry::where('lot_id', $lotId)->exists();
    }

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

        // Ticket UNI : le code est unique parmi TOUTES les bandes (casse, accents et espaces ignorés). Garde-fou du
        // point de passage unique : un appelant qui n'a pas validé (ou qui a perdu une course) ne crée pas de doublon.
        if (UniqueNormalise::estPris('livestock_lots', 'code', $donnees['code'], $id)) {
            throw ValidationException::withMessages(['code' => LivestockLot::messageCodePris(trim((string) $donnees['code']))]);
        }

        return DB::transaction(function () use ($donnees, $id, $date) {
            $lot = new LivestockLot();
            if ($id !== null) {
                $lot->id = $id;
            }
            $lot->fill([
                'code' => trim((string) $donnees['code']),
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
                $corrige = (int) $donnees['current_quantity'];
                // BS-Q4 : une valeur identique à l'effectif de la bande n'est pas une correction ; une vraie correction
                // sur une bande qui a des fiches passe par la fiche (cascade unique).
                if ($corrige !== (int) $lot->current_quantity && self::aDesFiches($lot->id)) {
                    throw ValidationException::withMessages(['quantity' => self::MESSAGE_EFFECTIF_PAR_LES_FICHES]);
                }
                $nouveau['current_quantity'] = $corrige;
            }

            // Ticket UNI : le code est immuable, SAUF pour corriger un doublon déjà en base — la bande dont le code est
            // partagé avec une autre se renomme (par l'exploitant, jamais automatiquement), vers un code libre.
            $code = array_key_exists('code', $donnees) ? trim((string) $donnees['code']) : '';
            if ($code !== '' && $code !== trim((string) $lot->code)) {
                if (! $lot->codeEstEnDoublon()) {
                    throw ValidationException::withMessages(['code' => LivestockLot::MESSAGE_CODE_IMMUABLE]);
                }
                if (UniqueNormalise::estPris('livestock_lots', 'code', $code, $lot->id)) {
                    throw ValidationException::withMessages(['code' => LivestockLot::messageCodePris($code)]);
                }
                $nouveau['code'] = $code;
            }

            $lot->fill($nouveau);
            if (! $lot->isDirty()) {
                return $lot;
            }

            $renomme = $lot->isDirty('code');
            $lot->save();
            AuditLog::record($renomme ? 'livestock_lot.renamed' : 'livestock_lot.updated', 'elevage');

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

            // BS-Q3 : une bande qui a encore des sujets vivants ne s'archive pas (rien n'est écrit, rien n'est perdu).
            if ((int) $lot->current_quantity > 0) {
                throw ValidationException::withMessages(['bande' => self::messageEffectifVivant((int) $lot->current_quantity)]);
            }

            $lot->update(['is_active' => false]);
            AuditLog::record('livestock_lot.archived', 'elevage');

            return self::ARCHIVEE_MAINTENANT;
        });
    }

    /**
     * BS-Q7 — restaure une bande archivée (Bandes & Sujets, et le poste à l'envoi). Une bande déjà en cours : aucun
     * effet, aucune trace. Refusée si une AUTRE bande en cours porte déjà ce code (comparaison sans casse, comme la
     * collation du serveur) : deux bandes en cours ne partagent jamais un code.
     *
     * @return string  [RESTAUREE_MAINTENANT] ou [DEJA_EN_COURS]
     *
     * @throws ValidationException  code déjà porté par une bande en cours
     */
    public function restaurer(string $id): string
    {
        return DB::transaction(function () use ($id) {
            $lot = LivestockLot::lockForUpdate()->findOrFail($id);

            if ($lot->is_active) {
                return self::DEJA_EN_COURS;
            }

            $pris = LivestockLot::where('is_active', true)
                ->where('id', '!=', $lot->id)
                ->whereRaw('lower(code) = ?', [mb_strtolower($lot->code)])
                ->exists();
            if ($pris) {
                throw ValidationException::withMessages(['bande' => self::messageCodePris($lot->code)]);
            }

            $lot->update(['is_active' => true]);
            AuditLog::record('livestock_lot.restored', 'elevage');

            return self::RESTAUREE_MAINTENANT;
        });
    }
}
