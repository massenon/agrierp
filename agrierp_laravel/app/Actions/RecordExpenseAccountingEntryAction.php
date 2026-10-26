<?php

namespace App\Actions;

use App\Exceptions\DepenseNonComptabilisableException;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\Expense;
use App\Models\TreasuryAccount;
use App\Services\AccountingEntryService;
use App\Services\DetteFournisseurService;

/**
 * Ticket 14.33 (Sprint 14) — ÉCRITURE COMPTABLE D'UNE DÉPENSE.
 *
 * 🔴 DÉFAUT TROUVÉ EN SIMULANT L'EXPLOITATION (ticket 14.31) : `SaisieDepenses` décrémentait la trésorerie sans rien
 * porter en charge ; 755 226 FCFA sortis de la caisse sans jamais réduire le résultat. Le CDC l'exige mot pour mot, §1.4
 * [M2] : « `RegisterExpense` → Débit Classe 6 / Crédit Classe 5 ».
 *
 * Ticket DEP1 — UNE DÉPENSE, PLUSIEURS LIGNES. L'écriture produite :
 *     Débit  chaque COMPTE de charge distinct des lignes ..... somme des montants des lignes de ce compte
 *     Crédit compte de trésorerie qui paie ................... le total (somme de toutes les lignes)
 *             — OU, pour une dépense À CRÉDIT (ticket DEP7), le compte 401 Fournisseurs (la dette envers le fournisseur)
 * Les débits sont REGROUPÉS par compte (deux lignes « 601 » donnent un seul débit 601), dans l'ordre des codes ; le
 * centre de coût de l'en-tête (facultatif) est porté par chaque ligne d'écriture (Comptabilité analytique). Datée de la
 * DÉPENSE : une charge appartient à la période où elle est engagée. Elle passe par `AccountingEntryService::record()`
 * (équilibre, exercice ouvert, numérotation, immuabilité) et l'appelant l'enveloppe dans UNE transaction avec l'en-tête
 * et les lignes : un refus annule tout.
 *
 * 🔴→✅ DEP1 — ÉCHEC = REFUS, JAMAIS SILENCE. Avant, une écriture impossible (compte de trésorerie sans compte du plan)
 * laissait une dépense sans pièce et un simple toast. Désormais [DepenseNonComptabilisableException] : la dépense n'est
 * pas enregistrée.
 */
class RecordExpenseAccountingEntryAction
{
    /**
     * @return AccountingEntry|null  null si la dépense est déjà comptabilisée (jamais de doublon) ou n'a aucune ligne
     *
     * @throws DepenseNonComptabilisableException  compte de trésorerie sans compte du plan comptable
     */
    public function execute(Expense $expense): ?AccountingEntry
    {
        if ($expense->accounting_entry_id !== null) {
            return null;   // déjà comptabilisée — jamais de doublon
        }

        $lignes = $expense->lines()->get();
        $total = round((float) $lignes->sum('amount'), 2);

        if ($lignes->isEmpty() || $total <= 0) {
            return null;
        }

        // Ticket DEP7 (DEP-Q3) — une dépense À CRÉDIT crédite le 401 du fournisseur (la dette) au lieu de la trésorerie : le même
        // compte, lu par le même service, que l'écriture d'un achat à crédit.
        if ($expense->on_credit) {
            $contrepartie = app(DetteFournisseurService::class)->compteFournisseurs();

            if (! $contrepartie) {
                throw new DepenseNonComptabilisableException(
                    'La dépense à crédit ne peut pas être enregistrée : le compte 401 « Fournisseurs » est absent du plan comptable. '
                    .'Aucune pièce comptable ne peut être passée.'
                );
            }
        } else {
            $contrepartie = $this->compteDeTresorerie($expense->treasury_account_id);

            if (! $contrepartie) {
                $compte = TreasuryAccount::find($expense->treasury_account_id);

                throw new DepenseNonComptabilisableException(
                    'La dépense ne peut pas être enregistrée : le compte de trésorerie « '.($compte?->label ?? '—')
                    .' » n\'est relié à aucun compte du plan comptable'.($compte?->account_code ? ' (compte '.$compte->account_code.' absent)' : '')
                    .'. Aucune pièce comptable ne peut être passée.'
                );
            }
        }

        $centre = $expense->cost_center_id;

        // Débits regroupés par compte de charge, dans l'ordre des codes (écriture stable et lisible).
        $parCompte = [];
        foreach ($lignes as $ligne) {
            $parCompte[$ligne->charge_account_id] = ($parCompte[$ligne->charge_account_id] ?? 0) + (float) $ligne->amount;
        }
        $comptes = ChartOfAccount::whereIn('id', array_keys($parCompte))->orderBy('code')->get(['id', 'code']);

        $ecriture = [];
        foreach ($comptes as $compte) {
            $ecriture[] = ['account_id' => $compte->id, 'cost_center_id' => $centre, 'debit' => round($parCompte[$compte->id], 2), 'credit' => 0];
        }
        $ecriture[] = ['account_id' => $contrepartie->id, 'cost_center_id' => $centre, 'debit' => 0, 'credit' => $total];

        $entry = app(AccountingEntryService::class)->record(
            lines: $ecriture,
            // Datée de la DÉPENSE elle-même : une charge appartient à la période où elle est engagée, pas à celle de sa saisie.
            entryDate: $expense->expense_date?->format('Y-m-d') ?? now()->format('Y-m-d'),
            reference: AccountingEntry::generateReference().' — Dépense '.$expense->label,
            sourceType: 'expense',
            sourceId: $expense->id,
        );

        $expense->update(['accounting_entry_id' => $entry->id]);

        return $entry;
    }

    /**
     * CONTRE-PASSATION d'une dépense archivée : une écriture d'annulation, de sens inverse, jamais la suppression de
     * l'originale (le grand livre est immuable).
     *
     * Ticket DEP1 — l'écriture est l'INVERSE EXACTE de l'écriture d'origine, relue ligne à ligne (comptes, montants,
     * centre de coût) : quelles que soient les lignes de la dépense, la charge extournée est exactement celle qui avait
     * été passée, même si la dépense est une ancienne dépense convertie.
     *
     *     Débit  compte de trésorerie ..... montant réintégré
     *     Crédit chaque compte de charge .. son montant
     *
     * Datée du JOUR DE L'ANNULATION, jamais de la dépense d'origine : antidater modifierait un résultat déjà arrêté, et
     * l'écriture serait refusée si la période d'origine est clôturée.
     */
    public function reverse(Expense $expense): ?AccountingEntry
    {
        if ($expense->accounting_entry_id === null) {
            return null;   // jamais comptabilisée : rien à annuler
        }

        $origine = AccountingEntry::with('lines')->find($expense->accounting_entry_id);

        if ($origine === null || $origine->lines->isEmpty()) {
            return null;
        }

        $inverse = $origine->lines->map(fn ($l) => [
            'account_id' => $l->account_id,
            'cost_center_id' => $l->cost_center_id,
            'debit' => (float) $l->credit,
            'credit' => (float) $l->debit,
        ])->all();

        return app(AccountingEntryService::class)->record(
            lines: $inverse,
            entryDate: now()->format('Y-m-d'),
            reference: AccountingEntry::generateReference().' — Annulation dépense '.$expense->label,
            sourceType: 'expense_reversal',
            sourceId: $expense->id,
        );
    }

    private function compteDeTresorerie(?string $treasuryAccountId): ?ChartOfAccount
    {
        if (! $treasuryAccountId) {
            return null;
        }

        $tresorerie = TreasuryAccount::find($treasuryAccountId);

        if (! $tresorerie || ! $tresorerie->account_code) {
            return null;
        }

        return ChartOfAccount::where('code', $tresorerie->account_code)->first();
    }
}
