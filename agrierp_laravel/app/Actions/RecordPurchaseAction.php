<?php

namespace App\Actions;

use App\Exceptions\AchatNonComptabilisableException;
use App\Models\AuditLog;
use App\Models\Payable;
use App\Models\Product;
use App\Models\Purchase;
use App\Models\PurchaseLine;
use App\Models\TreasuryAccount;
use Illuminate\Support\Facades\DB;

/**
 * Ticket 14.78 — ENREGISTRER UN ACHAT, EN UN SEUL ENDROIT.
 *
 * ⚠️⚠️ UN ACHAT PORTE CINQ EFFETS, PAS UN. Il crée la pièce ET ses lignes, il
 * ENTRE la marchandise au stock (recalcul du PMP), il DÉCAISSE la part réglée,
 * il ouvre une DETTE fournisseur si le règlement est partiel, et il passe son
 * ÉCRITURE SYSCOHADA. Enregistrer la pièce sans ses effets produirait
 * exactement le défaut déjà corrigé pour les ventes hors ligne (14.52), la
 * ponte (14.59) et les dépenses (14.62) : un enregistrement qui existe et ne
 * pèse sur rien, découvert des semaines plus tard au rapprochement.
 *
 * ⚠️ CETTE LOGIQUE VIVAIT DANS `Livewire\Achats\EnregistrerAchat::submitAchat()`.
 * Elle en est extraite ici parce que le poste Desktop enregistre désormais des
 * achats HORS LIGNE : deux copies de cinq effets auraient divergé — c'est une
 * question de temps, pas de discipline.
 */
class RecordPurchaseAction
{
    /**
     * @param  array<int, array{product_id: string, qty: float|int, unit_price: float|int}>  $lignes
     */
    public function execute(
        string $supplierId,
        array $lignes,
        string $paymentMode,
        string $treasuryAccountId,
        float $montantRegle,
        ?string $purchaseId = null,
        ?string $purchaseDate = null,
        ?string $purchaseOrderId = null,
        // Ticket S-T12 — date de l'entrée en stock (achat du poste : l'instant de l'achat) ; `null` = maintenant.
        ?\DateTimeInterface $instantDuMouvement = null,
    ): Purchase {
        $total = collect($lignes)->sum(
            fn (array $l) => (float) $l['qty'] * (float) $l['unit_price']
        );

        // Ticket 15.22 — un total nul ne produit AUCUNE écriture (ni dette, ni règlement) mais entrerait quand même
        // la marchandise au stock : refusé, comme tout achat non comptabilisable. Décision à valider (voir journal).
        if (round($total, 2) <= 0) {
            throw AchatNonComptabilisableException::montantNul();
        }

        // ⚠️ ON NE RÈGLE JAMAIS PLUS QUE LE TOTAL. Un poste qui enverrait un
        // montant payé supérieur créerait une dette NÉGATIVE et une écriture
        // déséquilibrée.
        $regle = min($montantRegle, $total);

        return DB::transaction(function () use (
            $supplierId, $lignes, $paymentMode, $treasuryAccountId,
            $total, $regle, $purchaseId, $purchaseDate, $purchaseOrderId, $instantDuMouvement
        ) {
            // ⚠️⚠️ L'IDENTIFIANT SE POSE HORS DE `create()`. `id` n'est pas
            // dans `$fillable` — et il ne doit pas y être : `create(['id' =>
            // …])` l'aurait IGNORE EN SILENCE, le serveur aurait forge son
            // propre UUID, et l'idempotence de l'envoi hors ligne serait morte
            // sans un message. Le meme achat rejoue serait entre deux fois au
            // stock. Verifie par le test « un achat rejoue ne change rien ».
            $achat = new Purchase();

            if ($purchaseId !== null) {
                $achat->id = $purchaseId;
            }

            $achat->fill([
                'supplier_id' => $supplierId,
                'purchase_order_id' => $purchaseOrderId,
                'payment_mode' => $paymentMode,
                'total' => $total,
                'purchase_date' => $purchaseDate ?? now()->format('Y-m-d'),
            ]);
            $achat->save();

            foreach ($lignes as $ligne) {
                PurchaseLine::create([
                    'purchase_id' => $achat->id,
                    'product_id' => $ligne['product_id'],
                    'qty' => $ligne['qty'],
                    'unit_price' => $ligne['unit_price'],
                ]);

                // ⚠️ JAMAIS `stock_qty` EN DIRECT. `AdjustStockAction` est le
                // seul point d'entrée réel d'une mutation de stock (ticket
                // 6.1) : c'est lui qui trace le mouvement et recalcule le PMP.
                $produit = Product::find($ligne['product_id']);
                if ($produit) {
                    app(AdjustStockAction::class)
                        ->execute($produit, (float) $ligne['qty'], 'purchase', $achat->id, $instantDuMouvement);
                }
            }

            if ($regle > 0) {
                TreasuryAccount::where('id', $treasuryAccountId)->decrement('balance', $regle);
            }

            // ⚠️ LA DETTE NE NAÎT QUE SI LE RÈGLEMENT EST PARTIEL, et elle porte
            // le TOTAL avec la part déjà réglée — jamais le seul reste dû : la
            // balance âgée a besoin des deux pour dire ce qui a été payé.
            if ($regle < $total) {
                Payable::create([
                    'supplier_id' => $supplierId,
                    'purchase_id' => $achat->id,
                    'amount' => $total,
                    'amount_paid' => $regle,
                    'due_date' => now()->addDays(30),
                    'status' => 'en_cours',
                ]);
            }

            $ecriture = app(RecordPurchaseAccountingEntryAction::class)
                ->execute($achat->fresh('lines'), $treasuryAccountId, $regle);

            AuditLog::record('purchase.recorded', 'achats');

            // ⚠️ JAMAIS SILENCIEUX. Une écriture manquante (compte absent du
            // plan) se trace, sinon le Compte de Résultat surestime la marge
            // sans que personne ne sache pourquoi.
            if ($ecriture === null) {
                // Tickets 15.21 / 15.22 — TOUT achat EXIGE son écriture, qu'il soit direct, reçu d'un bon de commande
                // ou rejoué depuis un poste : sans elle, la dette 401 naîtrait sans contrepartie. L'exception annule
                // toute la transaction : aucun résidu (ni achat, ni stock, ni dette, ni trésorerie).
                throw AchatNonComptabilisableException::compteManquant();
            }

            return $achat->fresh('lines');
        });
    }
}
