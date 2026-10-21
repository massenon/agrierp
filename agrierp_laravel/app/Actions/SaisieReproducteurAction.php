<?php

namespace App\Actions;

use App\Models\Animal;
use App\Models\AuditLog;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Ticket BS3 (décision BS-Q1 du 21/10/2026) — POINT DE PASSAGE UNIQUE du registre nominatif des reproducteurs :
 * enregistrer, modifier, sortir un sujet.
 *
 * Ces trois gestes vivaient dans `Livewire\Elevage\RegistreReproducteurs`. Le poste les fait désormais hors ligne
 * (rejoués à l'envoi par `SyncController::pushAnimals`) : les deux chemins passent ici, avec les mêmes règles, les
 * mêmes effets (audit compris) et les mêmes messages.
 *
 * ⚠️ RÈGLE D'OR DU TICKET 14.17, INCHANGÉE : IDENTIFIER UN SUJET N'EST PAS LE FAIRE ENTRER. Ni l'enregistrement, ni la
 * modification, ni la SORTIE ne touchent à `livestock_lots.current_quantity` — le sujet est déjà compté dans sa bande ;
 * le mouvement d'effectif se saisit dans la fiche journalière (cascade unique), qui fait foi sur les quantités. Il n'y
 * a donc aucune cascade à rejouer ici (le web n'en a pas non plus).
 *
 * ⚠️ UNE SORTIE EST UN ARCHIVAGE LOGIQUE : le statut, la date et le motif changent, la ligne et son historique restent
 * (Document 00 §7). Un sujet déjà sorti ne se re-sort pas : la même sortie rejouée est acquittée sans trace (renvoi du
 * poste), une sortie différente est refusée.
 *
 * Les règles de FORME (longueurs, types, unicité de l'identifiant) restent à l'appelant (`validate()` du composant,
 * `validator()` de l'envoi) ; ici, les règles qui lient plusieurs champs et les effets.
 */
class SaisieReproducteurAction
{
    /** Sortie de [sortir] : le sujet vient d'être sorti. */
    public const SORTI_MAINTENANT = 'sorti_maintenant';

    /** Sortie de [sortir] : la même sortie était déjà enregistrée, rien n'est écrit. */
    public const DEJA_SORTI = 'deja_sorti';

    public const MESSAGE_NAISSANCE_APRES_ENTREE = "La date de naissance ne peut pas être postérieure à la date d'entrée.";

    public const MESSAGE_SORTIE_AVANT_ENTREE = "La date de sortie ne peut pas précéder la date d'entrée du sujet.";

    /**
     * Décision BS-Q13 (21/10/2026) — l'identifiant d'un sujet enregistré ne change plus : les saillies (`mother_ref` /
     * `sire_ref`, du texte libre) et tout l'historique du sujet s'y rattachent par ce nom ; le changer les laisserait
     * orphelins. Refusé ici — donc au web (champ grisé, mais un formulaire forgé passe par le même point) et à l'envoi
     * du poste (rejet motivé, `conflict`). Un sujet qui n'existe pas encore garde la saisie libre.
     */
    public const MESSAGE_IDENTIFIANT_FIGE = "L'identifiant d'un sujet enregistré ne peut pas être modifié : les saillies et l'historique du sujet s'y rattachent par ce nom.";

    /** Décision BS-Q11 : la correspondance unique est celle du modèle. */
    public static function libelleStatut(string $statut): string
    {
        return Animal::libelleStatut($statut);
    }

    public static function messageDejaSorti(string $statut): string
    {
        return 'Ce reproducteur est déjà sorti ('.self::libelleStatut($statut).') : sa sortie ne peut pas être modifiée.';
    }

    /**
     * @param  array{identifier: string, species_id: string, lot_id?: ?string, sex: string, breed?: ?string,
     *               birth_date?: ?string, entry_date: string, origin?: ?string, cage?: ?string}  $donnees
     *
     * @throws ValidationException  naissance postérieure à l'entrée
     */
    public function enregistrer(array $donnees, ?string $id = null): Animal
    {
        $this->verifierLesDates($donnees['birth_date'] ?? null, (string) $donnees['entry_date']);

        return DB::transaction(function () use ($donnees, $id) {
            $animal = new Animal();
            if ($id !== null) {
                $animal->id = $id;
            }
            $animal->fill($this->champs($donnees) + ['status' => 'actif', 'is_active' => true]);
            $animal->save();

            AuditLog::record('animal.registered', 'elevage');

            return $animal;
        });
    }

    /**
     * La fiche du sujet (identité, bande, cage…). Le statut et la sortie ne changent JAMAIS ici ; une modification
     * identique n'écrit rien (idempotence des renvois du poste).
     *
     * @throws ValidationException  naissance postérieure à l'entrée (`birth_date`), identifiant changé (`identifier`)
     */
    public function modifier(string $id, array $donnees): Animal
    {
        $this->verifierLesDates($donnees['birth_date'] ?? null, (string) $donnees['entry_date']);

        return DB::transaction(function () use ($id, $donnees) {
            $animal = Animal::lockForUpdate()->findOrFail($id);

            if ((string) $donnees['identifier'] !== (string) $animal->identifier) {
                throw ValidationException::withMessages(['identifier' => self::MESSAGE_IDENTIFIANT_FIGE]);
            }

            $animal->fill($this->champs($donnees));

            if (! $animal->isDirty()) {
                return $animal;
            }

            $animal->save();
            AuditLog::record('animal.updated', 'elevage');

            return $animal;
        });
    }

    /**
     * @param  array{status: string, exit_date: string, exit_reason?: ?string}  $donnees  `status` : reforme, vendu ou mort
     * @return string  [SORTI_MAINTENANT] ou [DEJA_SORTI]
     *
     * @throws ValidationException  sortie avant l'entrée (`exit_date`), sujet déjà sorti autrement (`status`)
     */
    public function sortir(string $id, array $donnees): string
    {
        return DB::transaction(function () use ($id, $donnees) {
            $animal = Animal::lockForUpdate()->findOrFail($id);
            $date = substr((string) $donnees['exit_date'], 0, 10);
            $motif = ($donnees['exit_reason'] ?? null) ?: null;

            if (! $animal->isPresent()) {
                $memeSortie = $animal->status === $donnees['status']
                    && $animal->exit_date?->format('Y-m-d') === $date
                    && ($animal->exit_reason ?: null) === $motif;
                if ($memeSortie) {
                    return self::DEJA_SORTI;
                }

                throw ValidationException::withMessages(['status' => self::messageDejaSorti($animal->status)]);
            }

            if ($date < $animal->entry_date->format('Y-m-d')) {
                throw ValidationException::withMessages(['exit_date' => self::MESSAGE_SORTIE_AVANT_ENTREE]);
            }

            // Archivage LOGIQUE : le sujet change de statut, sa fiche et son historique restent consultables.
            $animal->update(['status' => $donnees['status'], 'exit_date' => $date, 'exit_reason' => $motif]);
            AuditLog::record('animal.exited', 'elevage');

            return self::SORTI_MAINTENANT;
        });
    }

    private function verifierLesDates(?string $naissance, string $entree): void
    {
        if ($naissance !== null && $naissance !== '' && substr($naissance, 0, 10) > substr($entree, 0, 10)) {
            throw ValidationException::withMessages(['birth_date' => self::MESSAGE_NAISSANCE_APRES_ENTREE]);
        }
    }

    /** @return array<string, mixed> */
    private function champs(array $donnees): array
    {
        return [
            'identifier' => $donnees['identifier'],
            'species_id' => $donnees['species_id'],
            'lot_id' => ($donnees['lot_id'] ?? null) ?: null,
            'category' => 'reproducteur',
            'sex' => $donnees['sex'],
            'breed' => ($donnees['breed'] ?? null) ?: null,
            'birth_date' => ($donnees['birth_date'] ?? null) ?: null,
            'entry_date' => $donnees['entry_date'],
            'origin' => ($donnees['origin'] ?? null) ?: null,
            'cage' => ($donnees['cage'] ?? null) ?: null,
        ];
    }
}
