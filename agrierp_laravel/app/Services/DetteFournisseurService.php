<?php

namespace App\Services;

use App\Exceptions\DepenseNonModifiableException;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\Expense;
use App\Models\Payable;
use Carbon\CarbonInterface;
use Illuminate\Support\Carbon;

/**
 * Ticket DEP7 (PRD `docs/prd/depenses-multilignes.md`, § 11 — DEP-Q3) — LA DETTE FOURNISSEUR, EN UN SEUL ENDROIT.
 *
 * Une dette fournisseur naissait dans `RecordPurchaseAction` (un achat réglé en partie) ; une dépense à crédit en ouvre
 * désormais une aussi. Deux copies auraient divergé (échéance, statut, compte 401) : les deux passent ICI.
 *
 *  - [ouvrir] : la dette (`payables`) d'un achat OU d'une dépense, statut `en_cours`, échéance 30 jours après la date de la
 *    pièce (aujourd'hui pour un achat saisi maintenant, comme avant) ;
 *  - [compteFournisseurs] : le compte 401, crédité par l'écriture d'un achat à crédit comme par celle d'une dépense à crédit ;
 *  - [apresImputation] : un règlement (`SupplierSettlementService`, l'écran « Dettes Fournisseurs », le poste) qui solde la
 *    dette d'une dépense passe cette dépense de `en_attente` à `payee` ;
 *  - [annulerPourDepense] : l'archivage d'une dépense à crédit retire sa dette (voir la méthode : refus si déjà réglée en
 *    tout ou partie).
 */
class DetteFournisseurService
{
    /** Délai de paiement accordé par défaut : 30 jours (celui des achats depuis toujours). */
    public const DELAI_JOURS = 30;

    /** Le compte 401 « Fournisseurs » du plan ; `null` si le plan est incomplet (l'appelant refuse, jamais de devinette). */
    public function compteFournisseurs(): ?ChartOfAccount
    {
        return ChartOfAccount::where('code', '401')->first();
    }

    /**
     * Ouvre la dette fournisseur d'une pièce : [$total] dû, [$regle] déjà payé (l'achat réglé en partie ; 0 pour une dépense).
     * ⚠️ La dette porte le TOTAL avec la part déjà réglée, jamais le seul reste dû : la balance âgée a besoin des deux.
     */
    public function ouvrir(
        string $supplierId,
        float $total,
        float $regle = 0,
        ?string $purchaseId = null,
        ?string $expenseId = null,
        ?CarbonInterface $datePiece = null,
    ): Payable {
        return Payable::create([
            'supplier_id' => $supplierId,
            'purchase_id' => $purchaseId,
            'expense_id' => $expenseId,
            'amount' => $total,
            'amount_paid' => $regle,
            'due_date' => ($datePiece !== null ? Carbon::instance($datePiece) : now())->copy()->addDays(self::DELAI_JOURS),
            'status' => 'en_cours',
        ]);
    }

    /** Après l'imputation d'un règlement sur [$dette] : la dette d'une dépense soldée passe cette dépense à `payee`. */
    public function apresImputation(Payable $dette): void
    {
        if ($dette->expense_id === null || $dette->balance > 0) {
            return;
        }

        // `update()` touche `updated_at` : le poste reçoit le nouveau statut au tirage suivant.
        Expense::whereKey($dette->expense_id)->where('status', '!=', 'payee')->get()->each->update(['status' => 'payee']);
    }

    /**
     * L'archivage d'une dépense à crédit RETIRE sa dette (l'écriture d'annulation, passée par l'appelant, extourne le 401).
     *
     * ⚠️ REFUSÉ si la dette a reçu un règlement, même partiel : l'argent est déjà sorti de la trésorerie (D 401 / C trésorerie)
     * et l'annulation de la charge laisserait un débit au 401 que rien n'explique — le règlement doit d'abord être régularisé
     * auprès du fournisseur (décision à confirmer, PRD DEP-Q9). Rien n'est alors écrit.
     *
     * La ligne `payables` est supprimée : c'est un échéancier, la trace comptable est l'écriture d'annulation et le journal
     * d'audit (la dette d'une dépense archivée n'a jamais existé financièrement).
     *
     * @throws DepenseNonModifiableException
     */
    public function verifierAnnulable(Expense $depense): void
    {
        $payee = (float) Payable::where('expense_id', $depense->id)->sum('amount_paid');

        if ($payee > 0) {
            throw new DepenseNonModifiableException(
                'Cette dépense à crédit est déjà réglée en tout ou partie ('.number_format($payee, 0, ',', ' ').' FCFA versés au fournisseur) : '
                .'elle ne peut plus être archivée. Régularisez d\'abord le règlement auprès du fournisseur.'
            );
        }
    }

    public function annulerPourDepense(Expense $depense): void
    {
        $this->verifierAnnulable($depense);

        if (Payable::where('expense_id', $depense->id)->delete() > 0) {
            AuditLog::record('expense.debt_cancelled', 'achats');
        }
    }
}
