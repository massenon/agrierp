<?php

namespace App\Actions;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\Purchase;
use App\Services\AccountingEntryService;
use Illuminate\Validation\ValidationException;

/**
 * Ticket 15.20 (D7) — CONTRE-PASSATION DE L'ÉCRITURE D'ACHAT lors d'un retour fournisseur.
 *
 * L'écriture d'achat d'origine (14.24) n'est JAMAIS modifiée : on passe une écriture INVERSE, datée du jour du RETOUR
 * (le fait), jamais de l'achat.
 *
 *     Crédit 601 / 445 .......... exactement les montants débités par l'écriture d'origine (HT, TVA)
 *     Débit  401 Fournisseurs ... part NON PAYÉE de l'achat (solde restant de la dette, que le retour annule)
 *     Débit  409 Fournisseurs débiteurs ... part DÉJÀ PAYÉE : le fournisseur nous doit cet argent
 *
 * ⚠️ AUCUN MOUVEMENT DE TRÉSORERIE : le retour ne ramène pas d'argent en caisse. Il fait naître une CRÉANCE (409) que
 * le remboursement (`SupplierRefundService`) éteindra contre une entrée en trésorerie.
 *
 * ⚠️ Les lignes d'origine sont RELUES, pas recalculées : si le taux de TVA du produit ou le régime de l'exploitation a
 * changé depuis l'achat, recalculer ferait contre-passer un autre montant que celui qui a été passé.
 *
 * ⚠️ Jamais de ligne à zéro. Une écriture d'origine absente, ou un compte manquant au plan, est un REFUS avec motif (la
 * transaction appelante annule alors stock et dette) : on ne devine pas une contre-passation.
 *
 * ⚠️ PROPOSITION COMPTABLE À FAIRE VALIDER PAR LE CABINET FAGUEZ (compte 409 et schéma).
 */
class RecordPurchaseReturnAccountingEntryAction
{
    /**
     * @param  float  $partNonPayee  solde ouvert de la dette de l'achat au moment du retour
     * @return array{entry: AccountingEntry, non_payee: float, payee: float}
     */
    public function execute(Purchase $achat, float $partNonPayee, string $date, string $returnBatchId): array
    {
        $origine = $achat->accounting_entry_id ? AccountingEntry::with('lines')->find($achat->accounting_entry_id) : null;

        if (! $origine) {
            throw ValidationException::withMessages([
                'purchase_id' => "Cet achat n'a pas d'écriture comptable (achat antérieur à la comptabilisation, ou réception de bon de commande) : "
                    .'la contre-passation est impossible. Faites régulariser son écriture par le comptable avant de le retourner.',
            ]);
        }

        $debits = $origine->lines->filter(fn ($l) => (float) $l->debit > 0);
        $total = round((float) $debits->sum('debit'), 2);

        if ($total <= 0) {
            throw ValidationException::withMessages(['purchase_id' => "L'écriture d'origine de cet achat est vide : contre-passation impossible."]);
        }

        $nonPayee = round(min(max($partNonPayee, 0), $total), 2);
        $payee = round($total - $nonPayee, 2);

        $lignes = [];

        foreach ($debits as $ligne) {
            $lignes[] = ['account_id' => $ligne->account_id, 'debit' => 0, 'credit' => round((float) $ligne->debit, 2)];
        }

        if ($nonPayee > 0) {
            $fournisseurs = ChartOfAccount::where('code', '401')->first();

            if (! $fournisseurs) {
                throw ValidationException::withMessages(['purchase_id' => 'Le compte 401 (fournisseurs) est absent du plan comptable : retour impossible.']);
            }

            $lignes[] = ['account_id' => $fournisseurs->id, 'debit' => $nonPayee, 'credit' => 0];
        }

        if ($payee > 0) {
            $debiteurs = ChartOfAccount::where('code', '409')->first();

            if (! $debiteurs) {
                throw ValidationException::withMessages(['purchase_id' => 'Le compte 409 (fournisseurs débiteurs) est absent du plan comptable : le retour d\'un achat déjà payé est impossible.']);
            }

            $lignes[] = ['account_id' => $debiteurs->id, 'debit' => $payee, 'credit' => 0];
        }

        $entry = app(AccountingEntryService::class)->record(
            lines: $lignes,
            entryDate: $date,
            reference: mb_substr(AccountingEntry::generateReference().' — Retour fournisseur '.strtoupper(substr($achat->id, 0, 8)), 0, 100),
            sourceType: 'purchase_return',
            sourceId: $returnBatchId,
        );

        return ['entry' => $entry, 'non_payee' => $nonPayee, 'payee' => $payee];
    }
}
