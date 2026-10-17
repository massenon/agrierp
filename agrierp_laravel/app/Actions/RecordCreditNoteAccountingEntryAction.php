<?php

namespace App\Actions;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\CreditNote;
use App\Services\AccountingEntryService;
use App\Services\TvaSettingService;
use App\Services\VatDeclarationService;

/**
 * Ticket 14.27 (Sprint 14) — ÉCRITURE COMPTABLE DE L'AVOIR CLIENT.
 *
 * Dernier flux financier du projet à ne produire aucune écriture, après les
 * ventes (14.23), les achats (14.24), la paie (14.25) et les amortissements
 * (14.26). La boucle comptable se ferme ici.
 *
 * Ce n'est pas une déduction de ma part : le prototype l'exige noir sur blanc.
 * L'étape 5 de l'assistant de retour (`retours-avoirs.html`) annonce comme
 * « conséquences automatiques à la validation » :
 *   « ✅ Génération d'un avoir · ✅ **Écriture comptable inverse** ·
 *     ✅ Mouvement de stock retour · ✅ **Mise à jour CA et créances** ·
 *     ✅ Notification »
 * Seuls l'avoir et le mouvement de stock étaient réellement câblés.
 *
 * ÉCRITURE PRODUITE (SYSCOHADA) — exactement l'INVERSE de l'écriture de vente
 * du ticket 14.23, sens des colonnes échangé :
 *     Débit  701 Ventes de produits ......... HT de l'avoir
 *     Débit  443 TVA facturée ............... TVA de l'avoir (si > 0)
 *     Crédit 411 Clients .................... TTC de l'avoir
 *
 * ⚠️ CONTREPARTIE AU COMPTE CLIENT (411), JAMAIS À LA TRÉSORERIE, ET MÊME
 * QUAND LA VENTE D'ORIGINE A ÉTÉ PAYÉE EN ESPÈCES. Un avoir constate une
 * DETTE envers le client ; il ne constate pas un décaissement. L'écran ne
 * demande à aucun moment si l'argent a été rendu, et son statut
 * `en_attente → traité` dit précisément le contraire : l'avoir reste ouvert
 * après sa création. Créditer 531 à cet instant affirmerait que la caisse
 * s'est vidée alors que personne n'a été remboursé — l'écart serait constaté
 * au premier rapprochement. C'est aussi ce que dit le prototype en nommant
 * « créances », et non « trésorerie », parmi les conséquences.
 *
 * Le remboursement effectif (débit 411 / crédit trésorerie) reste donc à
 * comptabiliser — voir la limite documentée sous `RetoursAvoirs`.
 *
 * ⚠️ AUCUNE SORTIE DE STOCK COMPTABLE ICI. Le projet ne tient pas d'inventaire
 * permanent : les achats vont directement en charges (601) sans compte de
 * stock de classe 3 mouvementé à chaque vente. Le retour physique du produit
 * est donc un mouvement de `products.stock_qty` (déjà assuré par
 * `AdjustStockAction`), pas une écriture — ajouter ici une contrepartie de
 * classe 3 introduirait un inventaire permanent que rien d'autre ne tient.
 */
class RecordCreditNoteAccountingEntryAction
{
    /**
     * @return AccountingEntry|null  null si l'écriture n'a pas pu être générée
     *                               — l'appelant DOIT alors avertir.
     */
    public function execute(CreditNote $creditNote): ?AccountingEntry
    {
        if ($creditNote->accounting_entry_id !== null) {
            return null;   // déjà comptabilisé — jamais de doublon
        }

        $ventes = ChartOfAccount::where('code', '701')->first();
        $clients = ChartOfAccount::where('code', '411')->first();

        if (! $ventes || ! $clients) {
            return null;   // plan comptable incomplet — signalé, jamais deviné
        }

        $ttc = round((float) $creditNote->amount, 2);

        if ($ttc <= 0) {
            return null;   // jamais d'écriture à zéro
        }

        [$ht, $tva] = $this->ventilerHtEtTva($creditNote, $ttc);

        $lignes = [
            ['account_id' => $ventes->id, 'debit' => $ht, 'credit' => 0],
        ];

        if ($tva > 0) {
            $tvaCollectee = ChartOfAccount::where('code', '443')->first();

            if (! $tvaCollectee) {
                return null;
            }

            $lignes[] = ['account_id' => $tvaCollectee->id, 'debit' => $tva, 'credit' => 0];
        }

        $lignes[] = ['account_id' => $clients->id, 'debit' => 0, 'credit' => $ttc];

        $entry = app(AccountingEntryService::class)->record(
            lines: $lignes,
            // ⚠️ Datée du JOUR DU RETOUR, jamais de la vente d'origine : la
            // vente est un fait de sa propre période, souvent déjà déclarée à
            // la DGI. Antidater l'avoir modifierait rétroactivement un chiffre
            // d'affaires arrêté, et l'écriture serait de surcroît refusée si
            // l'exercice d'origine est clôturé.
            entryDate: $creditNote->created_at?->format('Y-m-d') ?? now()->format('Y-m-d'),
            reference: AccountingEntry::generateReference().' — Avoir '.$creditNote->credit_note_number,
            sourceType: 'credit_note',
            sourceId: $creditNote->id,
        );

        $creditNote->update(['accounting_entry_id' => $entry->id]);

        return $entry;
    }

    /**
     * Ventilation HT / TVA du montant de l'avoir.
     *
     * Taux lu sur le produit retourné et ventilation confiée à
     * `VatDeclarationService` — même point de vérité que la Déclaration TVA
     * (14.7) et que l'écriture de vente (14.23), jamais un second calcul qui
     * pourrait en diverger.
     *
     * ⚠️ Le montant de l'avoir est SAISISSABLE : il est pré-rempli avec le
     * total de la ligne d'origine mais peut être réduit (retour partiel, ou
     * avoir commercial inférieur au prix payé). La ventilation part donc du
     * montant réellement retenu, jamais du total de la ligne vendue.
     *
     * Le HT absorbe l'arrondi résiduel : une écriture déséquilibrée serait
     * refusée par `AccountingEntryService` et ferait échouer le retour.
     *
     * @return array{0: float, 1: float}
     */
    private function ventilerHtEtTva(CreditNote $creditNote, float $ttc): array
    {
        // Ticket 14.38 : taux neutralisé si l'exploitation n'est pas assujettie.
        $taux = app(TvaSettingService::class)->tauxPour((float) ($creditNote->product?->tva_rate ?? 0)) / 100;

        $tva = round(app(VatDeclarationService::class)->tva($ttc, $taux), 2);

        return [round($ttc - $tva, 2), $tva];
    }
}
