<?php

namespace App\Services;

use App\Models\AccountingEntryLine;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use Illuminate\Validation\ValidationException;

/**
 * Ticket CP-1 — POINT DE PASSAGE UNIQUE DU PLAN COMPTABLE (créer, modifier, archiver un compte).
 *
 * Appelé par `Comptabilite\PlanComptable` (le web) ET par l'envoi du poste (`SyncController::pushChartOfAccounts`, droit
 * `manage-comptabilite`) : mêmes règles, mêmes messages, mêmes traces d'audit.
 *
 * ⚠️ ARCHIVAGE BLOQUÉ SI LE COMPTE EST DÉJÀ UTILISÉ par une ligne d'écriture : l'archiver casserait la lisibilité de toutes
 * les écritures passées qui le citent (contrainte `restrictOnDelete()` de `accounting_entry_lines.account_id`).
 */
class PlanComptableService
{
    public const MOTIF_COMPTE_UTILISE = "Impossible d'archiver : ce compte est déjà utilisé dans au moins une écriture comptable.";

    /**
     * Règles de saisie, sous les noms des propriétés de la page web (`code`, `label`, `class`).
     *
     * @return array<string, array<int, string>>
     */
    public function regles(?string $idModifie = null): array
    {
        return [
            'code' => ['required', 'string', 'max:20', 'unique:chart_of_accounts,code,'.$idModifie],
            'label' => ['required', 'string', 'max:255'],
            'class' => ['required', 'integer', 'between:1,9'],
        ];
    }

    /** @param array{code: string, label: string, class: int|string} $v */
    public function creer(array $v, ?string $id = null): ChartOfAccount
    {
        $compte = new ChartOfAccount();
        // `id` n'est pas remplissable : l'UUID du poste se pose HORS de `create()`, sans quoi il serait ignoré en silence.
        if ($id !== null) {
            $compte->id = $id;
        }
        $compte->fill(['code' => $v['code'], 'label' => $v['label'], 'class' => (int) $v['class'], 'is_active' => true]);
        $compte->save();

        AuditLog::record('chart_of_account.created', 'comptabilite');

        return $compte;
    }

    /** @param array{code: string, label: string, class: int|string} $v */
    public function modifier(ChartOfAccount $compte, array $v): ChartOfAccount
    {
        $compte->update(['code' => $v['code'], 'label' => $v['label'], 'class' => (int) $v['class']]);

        AuditLog::record('chart_of_account.updated', 'comptabilite');

        return $compte;
    }

    /**
     * @throws ValidationException le compte est déjà utilisé (le motif est celui que le web affiche)
     */
    public function archiver(ChartOfAccount $compte): ChartOfAccount
    {
        if (! $compte->is_active) {
            return $compte;
        }

        if (AccountingEntryLine::where('account_id', $compte->id)->exists()) {
            throw ValidationException::withMessages(['compte' => self::MOTIF_COMPTE_UTILISE]);
        }

        $compte->update(['is_active' => false]);

        AuditLog::record('chart_of_account.archived', 'comptabilite', null, $compte);

        return $compte;
    }
}
