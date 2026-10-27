<?php

namespace App\Actions;

use App\Models\AuditLog;
use App\Models\Employee;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Ticket RH-1 — POINT DE PASSAGE UNIQUE d'un employé : création, modification, archivage.
 *
 * Ces gestes vivaient dans `Livewire\RH\RegistreEmployes`. Le poste crée, modifie et archive désormais ses employés
 * (hors ligne, rejoués à l'envoi par `SyncController::pushEmployees`) : les deux chemins passent ici, avec les mêmes
 * règles, les mêmes effets (audit compris) et les mêmes messages.
 *
 * Règles :
 *  - création : `is_active` vrai, statut parmi `actif`, `conge`, `suspendu` ;
 *  - modification : tous les champs saisis ; un employé ARCHIVÉ ne se modifie plus ; une modification identique
 *    n'écrit rien (idempotence des renvois) ;
 *  - archivage : `is_active = false`, la ligne est gardée (Corbeille : audit `employee.archived` avec l'entité,
 *    ARC-Q2). Un second archivage n'a aucun effet, ni trace.
 */
class SaisieEmployeAction
{
    public const MESSAGE_ARCHIVE = 'Cet employé est archivé : il ne peut plus être modifié.';

    public const STATUTS = ['actif', 'conge', 'suspendu'];

    /** Règles de validation du web (`RegistreEmployes::saveEmployee`), sous les clés de la table. */
    public static function regles(): array
    {
        return [
            'first_name' => ['required', 'string', 'max:100'],
            'last_name' => ['required', 'string', 'max:100'],
            'position' => ['required', 'string', 'max:100'],
            'hire_date' => ['required', 'date'],
            'base_salary' => ['nullable', 'numeric', 'min:0'],
            'status' => ['required', 'in:'.implode(',', self::STATUTS)],
        ];
    }

    /**
     * @param  array{first_name: string, last_name: string, position: string, hire_date: string, base_salary?: mixed, status: string}  $donnees
     */
    public function creer(array $donnees, ?string $id = null): Employee
    {
        return DB::transaction(function () use ($donnees, $id) {
            $employe = new Employee();
            if ($id !== null) {
                // ⚠️ `id` n'est pas remplissable : `create(['id' => …])` l'ignorerait en silence (piège 14.78).
                $employe->id = $id;
            }
            $employe->fill($this->champs($donnees) + ['is_active' => true]);
            $employe->save();

            AuditLog::record('employee.created', 'rh');

            return $employe;
        });
    }

    /**
     * @param  array<string, mixed>  $donnees  mêmes clés que [creer]
     *
     * @throws ValidationException  employé archivé
     */
    public function modifier(string $id, array $donnees): Employee
    {
        return DB::transaction(function () use ($id, $donnees) {
            $employe = Employee::lockForUpdate()->findOrFail($id);
            if (! $employe->is_active) {
                throw ValidationException::withMessages(['employe' => self::MESSAGE_ARCHIVE]);
            }

            $employe->fill($this->champs($donnees));
            if (! $employe->isDirty()) {
                return $employe;
            }

            $employe->save();
            AuditLog::record('employee.updated', 'rh');

            return $employe;
        });
    }

    /** Rend vrai si l'employé vient d'être archivé, faux s'il l'était déjà (rien n'est écrit). */
    public function archiver(string $id): bool
    {
        return DB::transaction(function () use ($id) {
            $employe = Employee::lockForUpdate()->findOrFail($id);
            if (! $employe->is_active) {
                return false;
            }

            $employe->update(['is_active' => false]);
            AuditLog::record('employee.archived', 'rh', null, $employe);

            return true;
        });
    }

    /** La ligne envoyée par le poste est-elle identique à celle du serveur (renvoi d'un envoi déjà pris) ? */
    public function identique(Employee $employe, array $donnees): bool
    {
        $copie = $employe->replicate();
        $copie->fill($this->champs($donnees));

        return ! $copie->isDirty(array_keys($this->champs($donnees)));
    }

    /** @return array<string, mixed> */
    private function champs(array $donnees): array
    {
        return [
            'first_name' => trim((string) $donnees['first_name']),
            'last_name' => trim((string) $donnees['last_name']),
            'position' => trim((string) $donnees['position']),
            'hire_date' => substr((string) $donnees['hire_date'], 0, 10),
            'base_salary' => isset($donnees['base_salary']) && $donnees['base_salary'] !== '' ? (float) $donnees['base_salary'] : null,
            'status' => (string) $donnees['status'],
        ];
    }
}
