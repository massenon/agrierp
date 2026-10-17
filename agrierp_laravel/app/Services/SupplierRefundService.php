<?php

namespace App\Services;

use App\Actions\RecordSettlementAccountingEntryAction;
use App\Models\AuditLog;
use App\Models\Purchase;
use App\Models\Supplier;
use App\Models\SupplierRefund;
use App\Models\TreasuryAccount;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Ticket 15.20 (D8) — REMBOURSEMENT D'UN FOURNISSEUR : UNE SEULE IMPLÉMENTATION, pour la page « Liste d'Achats » ET
 * pour `/api/sync/push` (`supplier_refunds`).
 *
 * Ce que faisait la page web AVANT ce ticket (`submitRefund`) : `increment('balance')` sur le compte de trésorerie
 * choisi — sans écriture, sans lien avec un fournisseur ni avec un retour. Le solde du compte montait, le grand livre
 * de classe 5 ne bougeait pas : les DEUX livres de trésorerie divergeaient à chaque remboursement.
 *
 * ⚠️⚠️ CE QUE FAIT UN REMBOURSEMENT, DANS UNE SEULE TRANSACTION
 *   - plafond : `min(montant demandé, créance ouverte du fournisseur)` ; la créance ouverte est la part déjà payée des
 *     achats RETOURNÉS (compte 409) moins ce qui a déjà été remboursé. Au-delà, la part en trop n'entre pas en caisse ;
 *   - refus AVEC MOTIF s'il n'y a aucune créance ouverte (jamais d'écriture à zéro) ;
 *   - entrée en trésorerie (solde du compte) ET écriture Débit trésorerie / Crédit 409 : les DEUX livres bougent
 *     ensemble ou pas du tout (écriture impossible = tout est annulé : jamais d'argent encaissé sans écriture).
 *
 * ⚠️ IDEMPOTENCE PAR `id` DU POSTE : un renvoi est un acquittement, sans second encaissement.
 *
 * ⚠️ PROPOSITION COMPTABLE (Débit trésorerie / Crédit 409) À FAIRE VALIDER PAR LE CABINET FAGUEZ.
 */
class SupplierRefundService
{
    /** Créance ouverte sur un fournisseur : Σ parts payées des achats retournés − Σ remboursements déjà encaissés. */
    public function creanceOuverte(string $supplierId): float
    {
        $creance = (float) Purchase::where('supplier_id', $supplierId)->whereNotNull('returned_at')->sum('supplier_credit');
        $rembourse = (float) SupplierRefund::where('supplier_id', $supplierId)->sum('applied_amount');

        return round(max(0.0, $creance - $rembourse), 2);
    }

    /**
     * @param  string|null  $id  UUID du poste, conservé tel quel ; null = page web (UUID généré)
     * @return float part RÉELLEMENT encaissée (plafonnée à la créance ouverte)
     */
    public function rembourser(
        string $supplierId,
        float $montant,
        string $tresorerieId,
        ?string $date = null,
        ?string $id = null,
        ?string $deviceId = null,
    ): float {
        if ($id !== null && ($deja = SupplierRefund::find($id)) !== null) {
            return (float) $deja->applied_amount;   // renvoi : acquittement, rien n'est rejoué
        }

        $montant = round($montant, 2);

        if ($montant <= 0) {
            throw ValidationException::withMessages(['amount' => 'Le montant remboursé doit être supérieur à zéro.']);
        }

        $date ??= now()->toDateString();

        try {
            return DB::transaction(function () use ($supplierId, $montant, $tresorerieId, $date, $id, $deviceId) {
                $fournisseur = Supplier::lockForUpdate()->find($supplierId);

                if (! $fournisseur) {
                    throw ValidationException::withMessages(['supplier_id' => 'Fournisseur introuvable.']);
                }

                $tresorerie = TreasuryAccount::find($tresorerieId);

                if (! $tresorerie) {
                    throw ValidationException::withMessages(['treasury_account_id' => 'Compte de trésorerie introuvable.']);
                }

                $ouverte = $this->creanceOuverte($supplierId);

                // ⚠️ Rien à rembourser : refuser, plutôt que d'encaisser sans créance ni passer une écriture à zéro.
                if ($ouverte <= 0) {
                    throw ValidationException::withMessages([
                        'amount' => "Ce fournisseur n'a aucune créance ouverte : aucun achat payé n'a été retourné, ou tout a déjà été remboursé.",
                    ]);
                }

                $applique = round(min($montant, $ouverte), 2);

                $remboursement = new SupplierRefund();
                $remboursement->id = $id ?? (string) Str::uuid();
                $remboursement->fill([
                    'supplier_id' => $fournisseur->id,
                    'treasury_account_id' => $tresorerie->id,
                    'amount' => $montant,
                    'applied_amount' => $applique,
                    'refund_date' => $date,
                    'device_id' => $deviceId,
                ]);
                $remboursement->save();

                $tresorerie->increment('balance', $applique);

                $ecriture = app(RecordSettlementAccountingEntryAction::class)->receiveSupplierRefund(
                    $tresorerie->fresh(), $applique, $fournisseur->name, $remboursement->id, $date
                );

                // ⚠️ Jamais d'argent encaissé sans écriture : tout est annulé et le motif est rendu.
                if ($ecriture === null) {
                    throw ValidationException::withMessages([
                        'treasury_account_id' => "Écriture impossible : le compte 409 (fournisseurs débiteurs) est absent du plan comptable, ou ce compte de trésorerie n'a pas de compte comptable.",
                    ]);
                }

                AuditLog::record('supplier_refund.recorded', 'achats');

                return $applique;
            });
        } catch (UniqueConstraintViolationException $e) {
            if ($id !== null && ($deja = SupplierRefund::find($id)) !== null) {
                return (float) $deja->applied_amount;
            }

            throw $e;
        }
    }
}
