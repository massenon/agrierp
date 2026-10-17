<?php

namespace App\Services;

use App\Actions\RecordSettlementAccountingEntryAction;
use App\Models\AuditLog;
use App\Models\Payable;
use App\Models\Supplier;
use App\Models\SupplierPayment;
use App\Models\TreasuryAccount;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Ticket 15.16 — RÈGLEMENT D'UN FOURNISSEUR : UNE SEULE IMPLÉMENTATION.
 *
 * Il en existait deux copies (`DettesFournisseurs`, `ProfileFournisseur`) qui
 * avaient DIVERGÉ, et le poste en aurait fait une troisième.
 *
 * ⚠️⚠️ LA PART IMPUTÉE, PAS LE MONTANT SAISI. Le règlement est appliqué aux dettes
 * les plus anciennes d'abord (échéance croissante, FIFO) jusqu'à épuisement du
 * montant ou des dettes. Ce qui sort de la trésorerie ET ce qui est écrit au journal
 * est la part RÉELLEMENT imputée (`applied`) : un versement supérieur au total dû ne
 * solde que ce qui existe. `ProfileFournisseur` retirait le montant SAISI en entier
 * (trésorerie et écriture) — un trop-perçu fantôme de la ferme. Aligné ici, signalé
 * au ticket.
 *
 * ⚠️ Les deux livres de trésorerie (soldes des comptes ET écriture de classe 5) sont
 * mis à jour dans la MÊME transaction : si l'écriture est refusée (exercice clos),
 * rien n'a bougé.
 */
class SupplierSettlementService
{
    /**
     * @return float part réellement imputée aux dettes
     */
    public function regler(
        string $supplierId,
        float $montant,
        string $tresorerieId,
        ?string $date = null,
        ?string $paymentId = null,
        ?string $deviceId = null,
    ): float {
        return DB::transaction(function () use ($supplierId, $montant, $tresorerieId, $date, $paymentId, $deviceId) {
            $reste = $montant;

            $dettes = Payable::where('supplier_id', $supplierId)
                ->where('status', '!=', 'soldee')
                ->orderBy('due_date')
                ->lockForUpdate()
                ->get();

            // ⚠️ Rien à imputer : refuser, plutôt que de passer une écriture à zéro.
            if ($dettes->isEmpty()) {
                throw ValidationException::withMessages([
                    'amount' => "Ce fournisseur n'a aucune dette ouverte.",
                ]);
            }

            foreach ($dettes as $dette) {
                if ($reste <= 0) {
                    break;
                }

                $applique = min($reste, $dette->balance);
                $dette->amount_paid += $applique;
                $dette->status = $dette->balance <= 0 ? 'soldee' : 'en_cours';
                $dette->save();

                $reste -= $applique;
            }

            $applique = round($montant - max(0, $reste), 2);

            $tresorerie = TreasuryAccount::findOrFail($tresorerieId);
            $tresorerie->decrement('balance', $applique);

            $ecriture = app(RecordSettlementAccountingEntryAction::class)->payToSupplier(
                $tresorerie->fresh(),
                $applique,
                Supplier::find($supplierId)?->name,
                $dettes->first()?->id,
                $date,
            );

            if ($ecriture === null) {
                AuditLog::record('payable.accounting_entry_missing', 'comptabilite');
            }

            if ($paymentId !== null) {
                $paiement = new SupplierPayment();
                $paiement->id = $paymentId;
                $paiement->fill([
                    'supplier_id' => $supplierId,
                    'treasury_account_id' => $tresorerieId,
                    'amount' => $montant,
                    'applied_amount' => $applique,
                    'payment_date' => $date ?? now()->toDateString(),
                    'device_id' => $deviceId,
                ]);
                $paiement->save();
            }

            AuditLog::record('payable.payment_recorded', 'achats');

            return $applique;
        });
    }
}
