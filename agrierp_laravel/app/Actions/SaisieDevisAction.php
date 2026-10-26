<?php

namespace App\Actions;

use App\Models\AuditLog;
use App\Models\Quote;
use App\Services\AccountingEntryService;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Ticket DEV — POINT DE PASSAGE UNIQUE d'un devis : création, modification, changement de statut, archivage.
 *
 * Ces gestes vivaient dans `Livewire\Ventes\Devis`. Le poste crée, modifie, fait avancer et archive désormais ses
 * devis (hors ligne, rejoués à l'envoi par `SyncController::pushQuotes`) : les deux chemins passent ici, avec les
 * mêmes règles, les mêmes effets (audit compris) et les mêmes messages.
 *
 * Règles :
 *  - création : statut `brouillon`, actif, numéro `DEV-AAAA-NNN` attribué ICI par le serveur (jamais par le poste :
 *    deux postes hors ligne produiraient le même numéro sur deux documents). 🔴→✅ Un devis daté dans un exercice
 *    CLOS est refusé (motif R4, sous « Date du Devis ») : règle `refusExerciceClos`, un devis ne passe aucune écriture ;
 *  - modification : tous les champs saisis, sauf le numéro et le statut. Un devis ARCHIVÉ ou FACTURÉ ne se modifie plus ;
 *    un devis d'un exercice clos (date d'origine ou nouvelle date) non plus ; une modification identique n'écrit rien
 *    (idempotence des renvois) ;
 *  - statut : un seul pas du cycle `brouillon → envoyé → accepté | refusé`. Tout autre changement est refusé avec son
 *    motif ; le même statut redemandé ne fait rien. `facture` n'est atteint par aucun geste d'écran ni de poste (la
 *    conversion en facture n'existe pas encore). [aligner] fait avancer un devis jusqu'au statut du poste, pas à pas, en
 *    laissant la trace de chaque étape ;
 *  - archivage : `is_active = false`, la ligne est gardée. Un second archivage n'a aucun effet, ni trace.
 */
class SaisieDevisAction
{
    public const MESSAGE_ARCHIVE = 'Ce devis est archivé : il ne peut plus être modifié.';

    public const MESSAGE_FACTURE = 'Ce devis est facturé : il ne peut plus être modifié.';

    /** Pas autorisés du cycle de vie. */
    public const TRANSITIONS = [
        'brouillon' => ['envoye'],
        'envoye' => ['accepte', 'refuse'],
    ];

    /** Action du journal d'audit de l'arrivée dans chaque statut (libellés : `AuditLog::ACTION_LABELS`). */
    private const AUDIT_STATUT = [
        'envoye' => 'quote.sent',
        'accepte' => 'quote.accepted',
        'refuse' => 'quote.refused',
    ];

    /** Sortie de [archiver] : le devis l'était déjà, rien n'est écrit. */
    public const DEJA_ARCHIVE = 'deja_archive';

    /** Sortie de [archiver] : le devis vient d'être archivé. */
    public const ARCHIVE_MAINTENANT = 'archive_maintenant';

    public static function messageStatutInterdit(string $de, string $vers): string
    {
        return 'Changement de statut interdit : un devis « '.(Quote::STATUTS[$de] ?? $de).' » ne peut pas passer à « '
            .(Quote::STATUTS[$vers] ?? $vers).' ».';
    }

    /**
     * @param  array{customer_id: string, articles_description: string, amount: int|float|string, tva_rate: int|float|string,
     *               validity_days: int|string, quote_date: string, note?: ?string}  $donnees
     *
     * @throws ValidationException  exercice clos couvrant la date du devis
     */
    public function creer(array $donnees, ?string $id = null): Quote
    {
        $date = substr((string) $donnees['quote_date'], 0, 10);

        $this->refuserSiExerciceClos($date, 'quoteDate');

        return DB::transaction(function () use ($donnees, $id, $date) {
            $devis = new Quote();
            if ($id !== null) {
                // ⚠️ `id` n'est pas remplissable : `create(['id' => …])` l'ignorerait en silence (piège 14.78).
                $devis->id = $id;
            }
            $devis->fill($this->champs($donnees, $date) + [
                'quote_number' => Quote::generateQuoteNumber(),
                'status' => 'brouillon',
                'is_active' => true,
            ]);
            $devis->save();

            AuditLog::record('quote.created', 'ventes');

            return $devis;
        });
    }

    /**
     * @param  array<string, mixed>  $donnees  mêmes clés que [creer]
     *
     * @throws ValidationException  devis archivé, facturé, ou d'un exercice clos
     */
    public function modifier(string $id, array $donnees): Quote
    {
        return DB::transaction(function () use ($id, $donnees) {
            $devis = Quote::lockForUpdate()->findOrFail($id);
            $this->verifierModifiable($devis);

            $date = substr((string) $donnees['quote_date'], 0, 10);
            $nouveau = $this->champs($donnees, $date);

            $devis->fill($nouveau);
            if (! $devis->isDirty()) {
                return $devis;
            }

            // Le devis d'un exercice clos est en lecture seule ; il ne passe pas non plus dans un exercice clos.
            $this->refuserSiExerciceClos($devis->getOriginal('quote_date')->format('Y-m-d'), 'quoteDate');
            $this->refuserSiExerciceClos($date, 'quoteDate');

            $devis->save();
            AuditLog::record('quote.updated', 'ventes');

            return $devis;
        });
    }

    /**
     * Un pas du cycle de vie (`brouillon → envoyé → accepté | refusé`). Même statut : aucun effet, aucune trace.
     *
     * @throws ValidationException  pas interdit, devis archivé, ou d'un exercice clos
     */
    public function changerStatut(string $id, string $statut): Quote
    {
        return DB::transaction(function () use ($id, $statut) {
            $devis = Quote::lockForUpdate()->findOrFail($id);

            if ($devis->status === $statut && $devis->is_active) {
                return $devis;
            }
            if (! $devis->is_active) {
                throw ValidationException::withMessages(['devis' => self::MESSAGE_ARCHIVE]);
            }
            if (! in_array($statut, self::TRANSITIONS[$devis->status] ?? [], true)) {
                throw ValidationException::withMessages(['devis' => self::messageStatutInterdit($devis->status, $statut)]);
            }
            $this->refuserSiExerciceClos($devis->quote_date->format('Y-m-d'), 'devis');

            $devis->update(['status' => $statut]);
            AuditLog::record(self::AUDIT_STATUT[$statut], 'ventes');

            return $devis;
        });
    }

    /**
     * Fait avancer le devis jusqu'à [$statut], pas à pas (un poste hors ligne a pu l'envoyer puis l'accepter avant sa
     * première synchronisation). Un statut inatteignable (retour en arrière, `facture`) est refusé comme [changerStatut].
     */
    public function aligner(string $id, string $statut): Quote
    {
        $devis = Quote::findOrFail($id);

        if ($devis->status === $statut) {
            return $devis;
        }

        $chemin = $this->chemin($devis->status, $statut);
        if ($chemin === null) {
            throw ValidationException::withMessages(['devis' => self::messageStatutInterdit($devis->status, $statut)]);
        }
        foreach ($chemin as $etape) {
            $devis = $this->changerStatut($id, $etape);
        }

        return $devis;
    }

    /** @return string  [ARCHIVE_MAINTENANT] ou [DEJA_ARCHIVE] */
    public function archiver(string $id): string
    {
        return DB::transaction(function () use ($id) {
            $devis = Quote::lockForUpdate()->findOrFail($id);

            if (! $devis->is_active) {
                return self::DEJA_ARCHIVE;
            }
            $this->refuserSiExerciceClos($devis->quote_date->format('Y-m-d'), 'devis');

            $devis->update(['is_active' => false]);
            AuditLog::record('quote.archived', 'ventes', null, $devis);

            return self::ARCHIVE_MAINTENANT;
        });
    }

    /**
     * Le renvoi d'un devis déjà au serveur, tel quel : champs identiques (statut et archivage compris) = acquittement.
     *
     * @param  array<string, mixed>  $donnees
     */
    public function identique(Quote $devis, array $donnees): bool
    {
        $nouveau = $this->champs($donnees, substr((string) $donnees['quote_date'], 0, 10));
        $copie = (clone $devis)->fill($nouveau);

        return ! $copie->isDirty();
    }

    /**
     * Motif R4 (`AccountingEntryService::refusExerciceClos`) rendu en refus de validation sous [$champ] : « quoteDate »
     * (sous « Date du Devis ») pour une saisie, « devis » (toast d'erreur) pour un changement de statut ou un archivage.
     *
     * @throws ValidationException
     */
    private function refuserSiExerciceClos(string $date, string $champ): void
    {
        if ($refus = app(AccountingEntryService::class)->refusExerciceClos($date)) {
            throw ValidationException::withMessages([$champ => $refus]);
        }
    }

    /** @throws ValidationException */
    private function verifierModifiable(Quote $devis): void
    {
        if (! $devis->is_active) {
            throw ValidationException::withMessages(['devis' => self::MESSAGE_ARCHIVE]);
        }
        if ($devis->status === 'facture') {
            throw ValidationException::withMessages(['devis' => self::MESSAGE_FACTURE]);
        }
    }

    /** @return array<int, string>|null  les statuts à traverser pour aller de [$de] à [$vers], `null` si inatteignable */
    private function chemin(string $de, string $vers): ?array
    {
        $file = [[$de, []]];
        $vus = [$de => true];
        while ($file !== []) {
            [$courant, $etapes] = array_shift($file);
            foreach (self::TRANSITIONS[$courant] ?? [] as $suivant) {
                if (isset($vus[$suivant])) {
                    continue;
                }
                $vus[$suivant] = true;
                if ($suivant === $vers) {
                    return [...$etapes, $suivant];
                }
                $file[] = [$suivant, [...$etapes, $suivant]];
            }
        }

        return null;
    }

    /**
     * @param  array<string, mixed>  $donnees
     * @return array<string, mixed>
     */
    private function champs(array $donnees, string $date): array
    {
        return [
            'customer_id' => $donnees['customer_id'],
            'articles_description' => $donnees['articles_description'],
            'amount' => $donnees['amount'],
            'tva_rate' => $donnees['tva_rate'],
            'validity_days' => (int) $donnees['validity_days'],
            'quote_date' => $date,
            'note' => ($donnees['note'] ?? null) ?: null,
        ];
    }
}
