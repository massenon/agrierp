<?php

namespace App\Actions;

use App\Models\AuditLog;
use App\Models\Internship;
use App\Models\InternshipAbsence;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Ticket RH-2 — POINT DE PASSAGE UNIQUE d'un stagiaire et de ses absences : création, modification, absence
 * notée, absence archivée.
 *
 * Ces gestes vivaient dans `Livewire\RH\RegistreStagiaires`. Le poste les fait désormais hors ligne (rejoués à
 * l'envoi par `SyncController::pushInternships` / `pushInternshipAbsences`) : les deux chemins passent ici, avec les
 * mêmes règles, les mêmes effets (audit compris) et les mêmes messages.
 *
 * ⚠️ Un stagiaire n'a pas d'archivage au web (son statut « En cours / Terminé » se DÉDUIT de `end_date`) : il n'en a
 * pas non plus ici. Une absence, elle, s'archive (ticket 14.55 : jamais effacée, elle sert aux attestations).
 */
class SaisieStagiaireAction
{
    /** Règles de validation du web (`RegistreStagiaires::saveInternship`), sous les clés de la table. */
    public static function regles(): array
    {
        return [
            'first_name' => ['required', 'string', 'max:100'],
            'last_name' => ['required', 'string', 'max:100'],
            'school' => ['required', 'string', 'max:150'],
            'start_date' => ['required', 'date'],
            'end_date' => ['nullable', 'date', 'after_or_equal:start_date'],
            'monthly_fee' => ['nullable', 'numeric', 'min:0'],
            'fee_paid' => ['sometimes', 'boolean'],
            // ATT-1 : identité pour l'attestation de formation ; facultatifs, comme au web.
            'birth_date' => ['nullable', 'date'],
            'birth_place' => ['nullable', 'string', 'max:150'],
            'civilite' => ['sometimes', 'in:M.,Mme'],
        ];
    }

    /** Règles d'une absence (`RegistreStagiaires::saveAbsence`). */
    public static function reglesAbsence(): array
    {
        return [
            'internship_id' => ['required', 'uuid', 'exists:internships,id'],
            'absence_date' => ['required', 'date'],
            'reason' => ['nullable', 'string', 'max:255'],
            'is_active' => ['sometimes', 'boolean'],
        ];
    }

    public function creer(array $donnees, ?string $id = null): Internship
    {
        return DB::transaction(function () use ($donnees, $id) {
            $stagiaire = new Internship();
            if ($id !== null) {
                // ⚠️ `id` n'est pas remplissable : `create(['id' => …])` l'ignorerait en silence (piège 14.78).
                $stagiaire->id = $id;
            }
            $stagiaire->fill($this->champs($donnees));
            $stagiaire->save();

            AuditLog::record('internship.created', 'rh');

            return $stagiaire;
        });
    }

    public function modifier(string $id, array $donnees): Internship
    {
        return DB::transaction(function () use ($id, $donnees) {
            $stagiaire = Internship::lockForUpdate()->findOrFail($id);

            $stagiaire->fill($this->champs($donnees));
            if (! $stagiaire->isDirty()) {
                return $stagiaire;
            }

            $stagiaire->save();
            AuditLog::record('internship.updated', 'rh');

            return $stagiaire;
        });
    }

    public function identique(Internship $stagiaire, array $donnees): bool
    {
        $copie = $stagiaire->replicate();
        $copie->fill($this->champs($donnees));

        return ! $copie->isDirty(array_keys($this->champs($donnees)));
    }

    /**
     * Note une absence. Une absence DÉJÀ CONNUE (même identifiant) est rendue telle quelle : rien n'est réécrit.
     *
     * @param  array{internship_id: string, absence_date: string, reason?: ?string}  $donnees
     */
    public function absence(array $donnees, ?string $id = null): InternshipAbsence
    {
        return DB::transaction(function () use ($donnees, $id) {
            if ($id !== null && ($existante = InternshipAbsence::find($id)) !== null) {
                return $existante;
            }

            $absence = new InternshipAbsence();
            if ($id !== null) {
                $absence->id = $id;
            }
            $absence->fill([
                'internship_id' => $donnees['internship_id'],
                'absence_date' => substr((string) $donnees['absence_date'], 0, 10),
                'reason' => isset($donnees['reason']) && trim((string) $donnees['reason']) !== '' ? trim((string) $donnees['reason']) : null,
                'is_active' => true,
            ]);
            $absence->save();

            AuditLog::record('internship_absence.recorded', 'rh');

            return $absence;
        });
    }

    /**
     * 🔴→✅ TICKET 14.55 — UNE ABSENCE SUPPRIMÉE EST UNE TRACE EFFACÉE : archivée, elle reste restaurable.
     * Rend vrai si l'absence vient d'être archivée, faux si elle l'était déjà.
     */
    public function archiverAbsence(string $id): bool
    {
        return DB::transaction(function () use ($id) {
            $absence = InternshipAbsence::lockForUpdate()->findOrFail($id);
            if (! $absence->is_active) {
                return false;
            }

            $absence->update(['is_active' => false]);
            AuditLog::record('internship_absence.archived', 'rh', null, $absence);

            return true;
        });
    }

    /** @return array<string, mixed> */
    private function champs(array $donnees): array
    {
        $champs = [
            'first_name' => trim((string) $donnees['first_name']),
            'last_name' => trim((string) $donnees['last_name']),
            'school' => trim((string) $donnees['school']),
            'start_date' => substr((string) $donnees['start_date'], 0, 10),
            'end_date' => isset($donnees['end_date']) && $donnees['end_date'] !== '' ? substr((string) $donnees['end_date'], 0, 10) : null,
            'monthly_fee' => isset($donnees['monthly_fee']) && $donnees['monthly_fee'] !== '' ? (float) $donnees['monthly_fee'] : null,
            'fee_paid' => filter_var($donnees['fee_paid'] ?? false, FILTER_VALIDATE_BOOLEAN),
        ];

        // L'identité ATT-1 n'est touchée que si elle est envoyée (le web ne la saisit pas dans cette modale).
        if (array_key_exists('birth_date', $donnees)) {
            $champs['birth_date'] = $donnees['birth_date'] !== null && $donnees['birth_date'] !== '' ? substr((string) $donnees['birth_date'], 0, 10) : null;
        }
        if (array_key_exists('birth_place', $donnees)) {
            $champs['birth_place'] = $donnees['birth_place'] !== null && trim((string) $donnees['birth_place']) !== '' ? trim((string) $donnees['birth_place']) : null;
        }
        if (array_key_exists('civilite', $donnees) && in_array($donnees['civilite'], ['M.', 'Mme'], true)) {
            $champs['civilite'] = $donnees['civilite'];
        }

        return $champs;
    }

    /** Un stagiaire introuvable à l'envoi d'une absence (jamais créé, ou refusé dans le même envoi). */
    public static function refusStagiaireInconnu(): ValidationException
    {
        return ValidationException::withMessages(['internship_id' => 'Ce stagiaire est inconnu du serveur.']);
    }
}
