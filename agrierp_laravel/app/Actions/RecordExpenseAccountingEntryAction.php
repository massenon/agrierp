<?php

namespace App\Actions;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\Expense;
use App\Models\TreasuryAccount;
use App\Services\AccountingEntryService;

/**
 * Ticket 14.33 (Sprint 14) — ÉCRITURE COMPTABLE D'UNE DÉPENSE.
 *
 * 🔴 DÉFAUT TROUVÉ EN SIMULANT L'EXPLOITATION (ticket 14.31) : `SaisieDepenses`
 * décrémentait la trésorerie sans rien porter en charge. Les dépenses de
 * fonctionnement — carburant, électricité, eau, transport, entretien —
 * **n'apparaissaient nulle part au Compte de Résultat**. Sur la simulation :
 * 755 226 FCFA sortis de la caisse sans jamais réduire le résultat, qui était
 * donc surestimé d'autant.
 *
 * ⚠️ LE CDC L'EXIGE MOT POUR MOT, §1.4 [M2] :
 *     « **Règle** : `RegisterExpense` → Débit Classe 6 / Crédit Classe 5 »
 * et décrit l'écran comme l'« enregistrement comptable direct des charges de
 * fonctionnement (classe 6 SYSCOHADA) ». La règle n'était pas ambiguë, elle
 * n'était simplement pas implémentée.
 *
 * ÉCRITURE PRODUITE (SYSCOHADA) :
 *     Débit  compte de classe 6 choisi ......... montant de la dépense
 *     Crédit compte de trésorerie qui paie ..... même montant
 *
 * ⚠️ LE COMPTE DE CHARGE EST DÉJÀ SAISI, il n'était pas exploité. Le champ
 * `expenses.category` porte le libellé complet de l'écran — « 605 - Énergie »,
 * « 614 - Transports » — soit le code SYSCOHADA suivi de son intitulé. Le code
 * en est extrait ici plutôt que déduit d'une correspondance parallèle : c'est
 * le choix réel du comptable, et une seconde table de correspondance aurait
 * fini par diverger de la liste affichée à l'écran.
 */
class RecordExpenseAccountingEntryAction
{
    /**
     * @return AccountingEntry|null  null si l'écriture n'a pas pu être générée
     *                               — l'appelant DOIT alors avertir.
     */
    public function execute(Expense $expense): ?AccountingEntry
    {
        if ($expense->accounting_entry_id !== null) {
            return null;   // déjà comptabilisée — jamais de doublon
        }

        $montant = round((float) $expense->amount, 2);

        if ($montant <= 0) {
            return null;
        }

        $charge = $this->compteDeCharge($expense->category);
        $tresorerie = $this->compteDeTresorerie($expense->treasury_account_id);

        if (! $charge || ! $tresorerie) {
            return null;   // plan comptable incomplet — signalé, jamais deviné
        }

        $entry = app(AccountingEntryService::class)->record(
            lines: [
                ['account_id' => $charge->id, 'debit' => $montant, 'credit' => 0],
                ['account_id' => $tresorerie->id, 'debit' => 0, 'credit' => $montant],
            ],
            // Datée de la DÉPENSE elle-même : une charge appartient à la
            // période où elle est engagée, pas à celle de sa saisie.
            entryDate: $expense->expense_date?->format('Y-m-d') ?? now()->format('Y-m-d'),
            reference: AccountingEntry::generateReference().' — Dépense '.$expense->label,
            sourceType: 'expense',
            sourceId: $expense->id,
        );

        $expense->update(['accounting_entry_id' => $entry->id]);

        return $entry;
    }

    /**
     * CONTRE-PASSATION d'une dépense archivée : une écriture d'annulation, de
     * sens inverse, jamais la suppression de l'originale.
     *
     * ⚠️ LE GRAND LIVRE EST IMMUABLE. `archiveExpense()` réintègre la
     * trésorerie ; sans contre-passation, la charge resterait au Compte de
     * Résultat alors que l'argent est revenu — l'écart exact que le
     * rapprochement bancaire mettrait au jour, sans que rien n'explique
     * pourquoi. Effacer l'écriture d'origine serait pire : elle a été
     * justifiée, elle doit rester consultable, et c'est aussi la discipline
     * appliquée aux avoirs (14.27) et aux amortissements (14.26).
     *
     *     Débit  compte de trésorerie ..... montant réintégré
     *     Crédit compte de classe 6 ....... même montant
     */
    public function reverse(Expense $expense): ?AccountingEntry
    {
        if ($expense->accounting_entry_id === null) {
            return null;   // jamais comptabilisée : rien à annuler
        }

        $montant = round((float) $expense->amount, 2);
        $charge = $this->compteDeCharge($expense->category);
        $tresorerie = $this->compteDeTresorerie($expense->treasury_account_id);

        if ($montant <= 0 || ! $charge || ! $tresorerie) {
            return null;
        }

        return app(AccountingEntryService::class)->record(
            lines: [
                ['account_id' => $tresorerie->id, 'debit' => $montant, 'credit' => 0],
                ['account_id' => $charge->id, 'debit' => 0, 'credit' => $montant],
            ],
            // Datée du JOUR DE L'ANNULATION, jamais de la dépense d'origine :
            // antidater modifierait un résultat déjà arrêté, et l'écriture
            // serait refusée si la période d'origine est clôturée.
            entryDate: now()->format('Y-m-d'),
            reference: AccountingEntry::generateReference().' — Annulation dépense '.$expense->label,
            sourceType: 'expense_reversal',
            sourceId: $expense->id,
        );
    }

    /**
     * Compte de charge extrait du libellé choisi à l'écran.
     *
     * ⚠️ DEUX INCOHÉRENCES DU PROTOTYPE, SIGNALÉES ET NON RÉSOLUES ICI :
     *   - la liste propose « 621 - Salaires », alors que la paie est
     *     comptabilisée en 661 Charges de personnel (ticket 14.25) : deux
     *     comptes différents pour la même nature de charge ;
     *   - « 614 - Transports » et « 624 - Transports » y figurent tous deux,
     *     avec le même intitulé.
     * Les deux comptes sont créés au plan comptable pour que l'écran reste
     * fonctionnel, mais trancher lequel retenir relève du client — arbitrer
     * seul reviendrait à réécrire silencieusement son plan comptable.
     */
    private function compteDeCharge(?string $categorie): ?ChartOfAccount
    {
        if (! $categorie) {
            return null;
        }

        // « 605 - Énergie » → « 605 ». Le format vient de l'écran lui-même.
        if (! preg_match('/^\s*(\d{2,4})/', $categorie, $trouve)) {
            return null;
        }

        return ChartOfAccount::where('code', $trouve[1])->where('class', 6)->first();
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
