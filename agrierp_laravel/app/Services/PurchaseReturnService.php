<?php

namespace App\Services;

use App\Actions\AdjustStockAction;
use App\Actions\RecordPurchaseReturnAccountingEntryAction;
use App\Models\AuditLog;
use App\Models\Payable;
use App\Models\Product;
use App\Models\Purchase;
use App\Models\PurchaseReturn;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Ticket 15.20 — RETOUR FOURNISSEUR : UNE SEULE IMPLÉMENTATION, pour la page « Liste d'Achats » ET pour
 * `/api/sync/push` (`purchase_returns`).
 *
 * D6 : le retour est l'ANNULATION COMPLÈTE de l'achat (le retour partiel est un autre ticket).
 * D7 : contre-passation de l'écriture d'achat (écriture inverse datée du jour du retour), part non payée de la dette
 *      annulée, part déjà payée = créance sur le fournisseur (compte 409).
 *
 * Ce que faisait la page web AVANT ce ticket (`confirmReturnPurchase`) : créer des `PurchaseReturn` et décrémenter le
 * stock — rien d'autre. Ni la dette (restée due au fournisseur pour une marchandise rendue), ni la trésorerie, ni le
 * journal (601 restait débité) ; et rien n'empêchait de retourner deux fois le même achat (double décrément, stock
 * négatif).
 *
 * ⚠️⚠️ CE QUE FAIT UN RETOUR, TOUT DANS UNE SEULE TRANSACTION
 *   1. un `PurchaseReturn` par ligne d'achat ;
 *   2. le stock : `AdjustStockAction` (jamais en direct), refusé s'il deviendrait NÉGATIF ;
 *   3. la dette : la part non payée est annulée (`amount` ramené à `amount_paid`, statut soldée) ;
 *   4. le journal : contre-passation (`RecordPurchaseReturnAccountingEntryAction`) ;
 *   5. `purchases.returned_at` (descend au poste) et `purchases.supplier_credit` (part payée = créance 409).
 *  Exercice clos/absent, stock insuffisant, compte manquant : tout est annulé, motif rendu, ni stock ni dette faux.
 *
 * ⚠️ IDEMPOTENCE PAR L'UUID DU RETOUR (`return_batch_id`, fourni par le poste). Un renvoi dont l'accusé s'est perdu est
 * un ACQUITTEMENT, jamais un rejeu (sinon le stock serait décrémenté deux fois). Le contrôle précède toute validation :
 * un renvoi acquitté le reste même si, entre-temps, l'exercice a été clos. Filets : `returned_at` + index unique sur
 * `purchase_returns.purchase_line_id` (deux envois simultanés).
 *
 * ⚠️ LE POSTE N'ENVOIE JAMAIS D'AJUSTEMENT DE STOCK POUR UN RETOUR : le serveur décrémente (voir
 * `SyncController::pushStockAdjustments`).
 *
 * ⚠️ PROPOSITIONS COMPTABLES (compte 409, contre-passation) À FAIRE VALIDER PAR LE CABINET FAGUEZ.
 */
class PurchaseReturnService
{
    /**
     * @param  string|null  $id  UUID du retour (poste) ; null = page web (UUID généré)
     * @return Collection<int, PurchaseReturn> les lignes de retour (existantes si renvoi)
     */
    public function annuler(
        string|Purchase $achat,
        string $motif,
        ?string $date = null,
        ?string $id = null,
        ?string $deviceId = null,
    ): Collection {
        $achatId = $achat instanceof Purchase ? $achat->id : $achat;

        if ($id !== null && ($deja = PurchaseReturn::where('return_batch_id', $id)->get())->isNotEmpty()) {
            if ($deja->first()->purchase_id !== $achatId) {
                throw ValidationException::withMessages(['id' => 'Cet identifiant de retour est déjà utilisé pour un autre achat.']);
            }

            return $deja;   // renvoi : acquittement, rien n'est rejoué
        }

        $motif = trim($motif);

        if ($motif === '') {
            throw ValidationException::withMessages(['reason' => 'Le motif du retour est obligatoire.']);
        }

        $date = Carbon::parse($date ?? now()->toDateString())->toDateString();

        if ($date > now()->toDateString()) {
            throw ValidationException::withMessages(['return_date' => 'La date du retour ne peut pas être dans le futur.']);
        }

        $id ??= (string) Str::uuid();

        try {
            return DB::transaction(function () use ($achatId, $motif, $date, $id, $deviceId) {
                $achat = Purchase::with('lines')->lockForUpdate()->find($achatId);

                if (! $achat) {
                    throw ValidationException::withMessages(['purchase_id' => 'Achat introuvable.']);
                }

                if ($achat->estRetourne() || $achat->returns()->exists()) {
                    throw ValidationException::withMessages([
                        'purchase_id' => 'Cet achat a déjà été retourné'.($achat->returned_at ? ' le '.$achat->returned_at->format('d/m/Y') : '').' : un achat ne peut être annulé qu\'une fois.',
                    ]);
                }

                if ($achat->lines->isEmpty()) {
                    throw ValidationException::withMessages(['purchase_id' => "Cet achat n'a aucune ligne : rien à retourner."]);
                }

                if ($achat->purchase_date && $date < $achat->purchase_date->format('Y-m-d')) {
                    throw ValidationException::withMessages(['return_date' => "La date du retour ne peut pas précéder celle de l'achat."]);
                }

                // ⚠️ Le stock ne descend JAMAIS sous zéro : agrégé par produit (deux lignes du même produit), verrouillé.
                $parProduit = $achat->lines->groupBy('product_id')->map(fn ($l) => round((float) $l->sum('qty'), 2));
                $produits = Product::whereIn('id', $parProduit->keys())->lockForUpdate()->get()->keyBy('id');

                foreach ($parProduit as $produitId => $quantite) {
                    $produit = $produits->get($produitId);

                    if (! $produit) {
                        throw ValidationException::withMessages(['purchase_id' => 'Un produit de cet achat est introuvable : retour impossible.']);
                    }

                    if (round((float) $produit->stock_qty, 2) < $quantite) {
                        throw ValidationException::withMessages([
                            'stock' => "Stock insuffisant pour retourner « {$produit->name} » : {$quantite} à rendre, {$produit->stock_qty} en stock. "
                                .'Le stock ne peut pas devenir négatif.',
                        ]);
                    }
                }

                // La part NON PAYÉE = solde ouvert de la dette de l'achat (paiements ultérieurs déjà déduits).
                $dette = Payable::where('purchase_id', $achat->id)->lockForUpdate()->first();
                $nonPayee = ($dette && $dette->status !== 'soldee') ? max(0.0, $dette->balance) : 0.0;

                $mouvement = Carbon::parse($date)->setTimeFrom(now());
                $lignesRetour = collect();

                foreach ($achat->lines as $ligne) {
                    $retour = new PurchaseReturn();
                    $retour->fill([
                        'purchase_id' => $achat->id,
                        'product_id' => $ligne->product_id,
                        'qty' => $ligne->qty,
                        'reason' => $motif,
                        'return_batch_id' => $id,
                        'purchase_line_id' => $ligne->id,
                        'return_date' => $date,
                        'device_id' => $deviceId,
                    ]);
                    $retour->save();
                    $lignesRetour->push($retour);

                    // ⚠️ JAMAIS `stock_qty` EN DIRECT : le mouvement est écrit dans le même appel.
                    app(AdjustStockAction::class)->execute(
                        $produits->get($ligne->product_id),
                        -(float) $ligne->qty,
                        'purchase_return',
                        $retour->id,
                        $mouvement,
                        $motif,
                    );
                }

                // La contre-passation lit l'écriture d'origine, refuse si elle manque, et respecte l'exercice.
                $compta = app(RecordPurchaseReturnAccountingEntryAction::class)->execute($achat, $nonPayee, $date, $id);

                // La part non payée de la dette est ANNULÉE : le fournisseur ne la réclame plus, la marchandise est rendue.
                // `amount` est ramené à `amount_paid` (les requêtes de dettes ouvertes comparent les deux).
                if ($dette && $dette->status !== 'soldee') {
                    $dette->amount = $dette->amount_paid;
                    $dette->status = 'soldee';
                    $dette->save();
                }

                $achat->forceFill([
                    'returned_at' => now(),
                    'supplier_credit' => $compta['payee'],
                ])->save();

                AuditLog::record('purchase.returned', 'achats');

                return $lignesRetour;
            });
        } catch (UniqueConstraintViolationException $e) {
            // Deux envois simultanés : l'autre a gagné. Même retour = renvoi ; sinon l'achat est déjà retourné.
            if (($deja = PurchaseReturn::where('return_batch_id', $id)->get())->isNotEmpty() && $deja->first()->purchase_id === $achatId) {
                return $deja;
            }

            throw ValidationException::withMessages(['purchase_id' => "Cet achat a déjà été retourné : un achat ne peut être annulé qu'une fois."]);
        }
    }
}
