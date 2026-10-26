<?php

namespace App\Actions;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\Purchase;
use App\Models\TreasuryAccount;
use App\Services\AccountingEntryService;
use App\Services\DetteFournisseurService;
use App\Services\TvaSettingService;
use App\Services\VatDeclarationService;

/**
 * Ticket 14.24 (Sprint 14) — GÉNÉRATION AUTOMATIQUE DE L'ÉCRITURE D'ACHAT.
 *
 * Pendant du ticket 14.23 côté fournisseurs. Comme les ventes, **aucun achat
 * ne produisait d'écriture** : les charges n'apparaissaient nulle part dans la
 * comptabilité, et le Compte de Résultat affichait une marge égale au chiffre
 * d'affaires — un résultat net systématiquement surestimé.
 *
 * ÉCRITURE PRODUITE (SYSCOHADA), à plusieurs lignes :
 *     Débit  601 Achats de marchandises .......... HT
 *     Débit  445 TVA récupérable ................. TVA (si > 0)
 *     Crédit compte de trésorerie choisi ......... montant réglé (si > 0)
 *     Crédit 401 Fournisseurs .................... reste à payer (si > 0)
 *
 * ⚠️ LE PAIEMENT PARTIEL EST LA RAISON D'ÊTRE DE CETTE FORME. `EnregistrerAchat`
 * permet de régler une partie seulement et crée une dette fournisseur pour le
 * solde. Une écriture réduite à une paire débit/crédit ne pourrait pas le
 * représenter — le CDC prévoit d'ailleurs explicitement des lignes multiples
 * (`accounting_entries` / `accounting_entry_lines` séparées, jamais une paire
 * simple codée en dur).
 *
 * ⚠️ CONTREPARTIE DE TRÉSORERIE LUE SUR LE COMPTE RÉELLEMENT CHOISI
 * (`treasury_accounts.account_code`), et non déduite du mode de paiement : sur
 * cet écran la caissière sélectionne explicitement le compte qui paie. Déduire
 * le compte du mode de règlement ignorerait ce choix — deux comptes bancaires
 * distincts partagent le même mode « virement ».
 */
class RecordPurchaseAccountingEntryAction
{
    /**
     * @param  float  $montantRegle  part réellement payée à l'enregistrement
     * @return AccountingEntry|null  null si l'écriture n'a pas pu être générée
     *                               — l'appelant DOIT alors avertir.
     */
    public function execute(Purchase $purchase, string $treasuryAccountId, float $montantRegle): ?AccountingEntry
    {
        if ($purchase->accounting_entry_id !== null) {
            return null;   // déjà comptabilisé — jamais de doublon
        }

        $achats = ChartOfAccount::where('code', '601')->first();

        if (! $achats) {
            return null;   // plan comptable incomplet — signalé, jamais deviné
        }

        $total = round((float) $purchase->total, 2);
        $regle = round(min(max($montantRegle, 0), $total), 2);
        $reste = round($total - $regle, 2);

        [$ht, $tva] = $this->ventilerHtEtTva($purchase, $total);

        $lignes = [
            ['account_id' => $achats->id, 'debit' => $ht, 'credit' => 0],
        ];

        if ($tva > 0) {
            $tvaDeductible = ChartOfAccount::where('code', '445')->first();

            if (! $tvaDeductible) {
                return null;
            }

            $lignes[] = ['account_id' => $tvaDeductible->id, 'debit' => $tva, 'credit' => 0];
        }

        if ($regle > 0) {
            $compteTresorerie = $this->compteDeTresorerie($treasuryAccountId);

            if (! $compteTresorerie) {
                return null;
            }

            $lignes[] = ['account_id' => $compteTresorerie->id, 'debit' => 0, 'credit' => $regle];
        }

        if ($reste > 0) {
            $fournisseurs = app(DetteFournisseurService::class)->compteFournisseurs();

            if (! $fournisseurs) {
                return null;
            }

            $lignes[] = ['account_id' => $fournisseurs->id, 'debit' => 0, 'credit' => $reste];
        }

        $entry = app(AccountingEntryService::class)->record(
            lines: $lignes,
            entryDate: $purchase->purchase_date?->format('Y-m-d') ?? now()->format('Y-m-d'),
            reference: AccountingEntry::generateReference().' — Achat '.strtoupper(substr($purchase->id, 0, 8)),
            sourceType: 'purchase',
            sourceId: $purchase->id,
        );

        $purchase->update(['accounting_entry_id' => $entry->id]);

        return $entry;
    }

    /** Compte comptable du compte de trésorerie réellement sélectionné. */
    private function compteDeTresorerie(string $treasuryAccountId): ?ChartOfAccount
    {
        $tresorerie = TreasuryAccount::find($treasuryAccountId);

        if (! $tresorerie || ! $tresorerie->account_code) {
            return null;
        }

        return ChartOfAccount::where('code', $tresorerie->account_code)->first();
    }

    /**
     * Ventilation HT / TVA, dérivée ligne à ligne depuis `products.tva_rate`
     * par `VatDeclarationService` — même point de vérité que la Déclaration
     * TVA (ticket 14.7) et que l'écriture de vente (ticket 14.23).
     *
     * Le HT absorbe l'arrondi résiduel : une écriture déséquilibrée serait
     * refusée par `AccountingEntryService` et ferait échouer l'achat.
     *
     * @return array{0: float, 1: float}
     */
    private function ventilerHtEtTva(Purchase $purchase, float $total): array
    {
        $service = app(VatDeclarationService::class);

        $tva = 0.0;

        foreach ($purchase->lines as $ligne) {
            $ttc = (float) ($ligne->qty * $ligne->unit_price);
            // Ticket 14.38 : aucune TVA ventilée si l'exploitation n'est pas
            // assujettie — la totalité va au compte de produit ou de charge.
            $taux = app(TvaSettingService::class)->tauxPour((float) ($ligne->product->tva_rate ?? 0)) / 100;

            $tva += $service->tva($ttc, $taux);
        }

        $tva = round($tva, 2);

        return [round($total - $tva, 2), $tva];
    }
}
