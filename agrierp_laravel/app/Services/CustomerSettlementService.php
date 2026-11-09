<?php

namespace App\Services;

use App\Actions\RecordSettlementAccountingEntryAction;
use App\Models\AuditLog;
use App\Models\Customer;
use App\Models\Receivable;
use App\Models\ReceivablePayment;
use App\Models\TreasuryAccount;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Ticket VC-1 — ENCAISSEMENT D'UNE CRÉANCE CLIENT : UNE SEULE IMPLÉMENTATION.
 *
 * Elle vivait en deux copies (`SuiviDettes::confirmPayment`, `ProfileClient::confirmRegularisation`) et le poste en aurait
 * fait une troisième. Désormais le web (les deux écrans) ET l'envoi des postes (`SyncController::pushReceivablePayments`)
 * passent ici : mêmes règles, mêmes effets, mêmes messages.
 *
 * ⚠️⚠️ LA PART IMPUTÉE, PAS LE MONTANT SAISI (même discipline que `SupplierSettlementService`, 15.16) : ce qui entre en
 * trésorerie ET ce qui est écrit au journal est la part RÉELLEMENT imputée aux créances. Un versement supérieur au dû ne
 * solde que ce qui existe ; la fiche client encaissait jusqu'ici le montant saisi en entier (un trop-perçu fantôme).
 *
 * Deux modes : une créance PRÉCISE (`$creanceId`, jamais au-delà de son solde — « Ajouter un Recouvrement ») ou le solde
 * GLOBAL du client (FIFO, échéance croissante — « Régulariser » de la fiche client).
 *
 * ⚠️ Les deux livres de trésorerie (solde du compte ET écriture D 5xx / C 411) bougent dans la MÊME transaction : si
 * l'écriture est refusée (exercice clos ou absent), rien n'a bougé.
 */
class CustomerSettlementService
{
    /**
     * @return float part réellement imputée aux créances
     *
     * @throws ValidationException aucune créance ouverte, créance d'un autre client, créance déjà soldée
     */
    public function encaisser(
        string $customerId,
        float $montant,
        string $tresorerieId,
        ?string $creanceId = null,
        ?string $date = null,
        ?string $paymentId = null,
        ?string $deviceId = null,
    ): float {
        return DB::transaction(function () use ($customerId, $montant, $tresorerieId, $creanceId, $date, $paymentId, $deviceId) {
            $creances = $creanceId !== null
                ? Receivable::where('id', $creanceId)->lockForUpdate()->get()
                : Receivable::where('customer_id', $customerId)
                    ->whereColumn('amount_paid', '<', 'amount')
                    ->orderBy('due_date')
                    ->lockForUpdate()
                    ->get();

            if ($creanceId !== null) {
                $cible = $creances->first();
                if ($cible === null) {
                    throw ValidationException::withMessages(['receivable_id' => 'Créance introuvable.']);
                }
                if ($cible->customer_id !== $customerId) {
                    throw ValidationException::withMessages(['receivable_id' => "Cette créance n'appartient pas à ce client."]);
                }
            }

            $ouvertes = $creances->filter(fn (Receivable $r) => $r->balance > 0);
            if ($ouvertes->isEmpty()) {
                throw ValidationException::withMessages([
                    'amount' => $creanceId !== null
                        ? 'Cette créance est déjà soldée : rien à encaisser.'
                        : "Ce client n'a aucune créance ouverte.",
                ]);
            }

            $reste = $montant;
            foreach ($ouvertes as $creance) {
                if ($reste <= 0) {
                    break;
                }
                $applique = min($reste, $creance->balance);
                $creance->amount_paid = round((float) $creance->amount_paid + $applique, 2);
                if ($creance->balance <= 0) {
                    $creance->status = 'soldee';
                }
                $creance->save();
                $reste -= $applique;
            }

            $applique = round($montant - max(0, $reste), 2);

            $tresorerie = TreasuryAccount::findOrFail($tresorerieId);
            $tresorerie->increment('balance', $applique);

            // 🔴→✅ TICKET 14.34 — UNE SEULE ÉCRITURE pour le versement, même lorsqu'il apure plusieurs créances en FIFO.
            $ecriture = app(RecordSettlementAccountingEntryAction::class)->collectFromCustomer(
                $tresorerie->fresh(),
                $applique,
                Customer::find($customerId)?->name,
                $creanceId ?? $ouvertes->first()?->id,
                $date,
            );

            if ($ecriture === null) {
                AuditLog::record('receivable.accounting_entry_missing', 'comptabilite');
            }

            if ($paymentId !== null) {
                $paiement = new ReceivablePayment();
                $paiement->id = $paymentId;
                $paiement->fill([
                    'customer_id' => $customerId,
                    'receivable_id' => $creanceId,
                    'treasury_account_id' => $tresorerieId,
                    'amount' => $montant,
                    'applied_amount' => $applique,
                    'payment_date' => $date ?? now()->toDateString(),
                    'device_id' => $deviceId,
                ]);
                $paiement->save();
            }

            AuditLog::record('receivable.payment_recorded', 'ventes');

            return $applique;
        });
    }
}
