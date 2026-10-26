<?php

namespace App\Actions;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\Sale;
use App\Services\AccountingEntryService;
use App\Services\TvaSettingService;
use App\Services\VatDeclarationService;

/**
 * Ticket 14.23 (Sprint 14) — GÉNÉRATION AUTOMATIQUE DE L'ÉCRITURE DE VENTE.
 *
 * 🔴 Le gap le plus lourd du projet, resté ouvert jusqu'ici : **aucune
 * opération financière ne générait son écriture comptable**. Ni la vente POS,
 * ni l'achat. Les seuls appels au service comptable venaient du Journal
 * (saisie manuelle) et de la clôture.
 *
 * Conséquence réelle : Bilan, Balance Générale, Grand Livre, Compte de
 * Résultat, États Financiers et Rapport Mensuel affichaient **zéro produit et
 * zéro charge**, quel que soit le nombre de ventes réellement encaissées. La
 * comptabilité était déconnectée de l'exploitation.
 *
 * Le CDC l'exige pourtant sans ambiguïté : « Toute opération financière
 * (vente, achat, paie, perte) doit déclencher la génération automatique de
 * l'écriture comptable correspondante via Listener/Use Case dédié. » Le
 * docblock de `JournalComptable` annonçait ce rétro-câblage comme « différé
 * au ticket 10.2 » — il n'a jamais eu lieu.
 *
 * ACTION DÉDIÉE, pas de logique dans le composant Livewire : c'est la
 * convention d'architecture du projet (le composant orchestre, l'Action
 * exécute) et cela rend la règle réutilisable par les Achats, la Paie et les
 * Retours, qui devront suivre.
 *
 * ÉCRITURE PRODUITE (SYSCOHADA) :
 *     Débit  contrepartie selon le mode de paiement ......... TTC
 *     Crédit 701 Ventes de produits ......................... HT
 *     Crédit 443 TVA facturée ............................... TVA (si > 0)
 */
class RecordSaleAccountingEntryAction
{
    /**
     * Compte de contrepartie selon le mode de règlement.
     *
     * Ticket 14.32 : passée en `public` pour être RÉUTILISÉE par
     * `CreditTreasuryForSaleAction`, qui doit mouvementer exactement le même
     * compte de trésorerie que celui débité ici. Deux tables séparées
     * finiraient par diverger, et les deux livres de trésorerie — la table
     * `treasury_accounts` et les comptes de classe 5 — cesseraient de
     * concorder.
     */
    public const COMPTES_PAR_MODE = [
        'especes' => '531',        // Caisse
        'mobile_money' => '521201', // Mobile Money
        'virement' => '521101',     // Banque
        'credit' => '411',          // Clients (créance)
    ];

    /**
     * @return AccountingEntry|null  null si l'écriture n'a pas pu être générée
     *                               — l'appelant DOIT alors avertir, jamais
     *                               ignorer en silence.
     */
    public function execute(Sale $sale): ?AccountingEntry
    {
        if ($sale->accounting_entry_id !== null) {
            return null;   // déjà comptabilisée — jamais de doublon
        }

        $codeContrepartie = self::COMPTES_PAR_MODE[$sale->payment_mode] ?? null;

        // ⚠️ Le mode « avance » n'est volontairement pas mappé : il consomme
        // une avance client déjà encaissée. PHRASE DATÉE, RELUE AU TICKET 15.19 : le compte
        // d'avances (419) existe désormais au plan comptable, ce n'est donc plus la raison.
        // Ce qui manque est la CONSOMMATION elle-même : la caisse ne choisit pas l'avance, ne
        // baisse pas `amount_used` et ne passe pas Débit 419 / Crédit 701 (+ 443). Ticket à
        // ouvrir ; tant qu'il ne l'est pas, une vente « Déduire de l'avance » ne produit aucune
        // écriture, et l'avance reste entière.
        if ($codeContrepartie === null) {
            return null;
        }

        $contrepartie = ChartOfAccount::where('code', $codeContrepartie)->first();
        $ventes = ChartOfAccount::where('code', '701')->first();

        if (! $contrepartie || ! $ventes) {
            return null;   // plan comptable incomplet — signalé, jamais deviné
        }

        [$ht, $tva] = $this->ventilerHtEtTva($sale);

        $lignes = [
            ['account_id' => $contrepartie->id, 'debit' => round((float) $sale->total, 2), 'credit' => 0],
            ['account_id' => $ventes->id, 'debit' => 0, 'credit' => $ht],
        ];

        if ($tva > 0) {
            $tvaCollectee = ChartOfAccount::where('code', '443')->first();

            if (! $tvaCollectee) {
                return null;
            }

            $lignes[] = ['account_id' => $tvaCollectee->id, 'debit' => 0, 'credit' => $tva];
        }

        $entry = app(AccountingEntryService::class)->record(
            lines: $lignes,
            // 🔴→✅ TICKET 14.71 — `created_at` EST LA DATE DU TIRAGE, pas
            // celle de la vente. Une vente encaissee hors ligne le 28/07 et
            // remontee le 02/08 passait son ecriture SYSCOHADA en aout :
            // produit impute a la mauvaise periode, balance des deux mois
            // fausse. `sold_at` porte l'heure reelle du comptoir ; le repli
            // sur `created_at` couvre l'historique anterieur a la colonne.
            entryDate: $sale->date_effective?->format('Y-m-d')
                ?? now()->format('Y-m-d'),
            reference: AccountingEntry::generateReference().' — Vente '.strtoupper(substr($sale->id, 0, 8)),
            sourceType: 'sale',
            sourceId: $sale->id,
        );

        $sale->update(['accounting_entry_id' => $entry->id]);

        return $entry;
    }

    /**
     * Ventilation HT / TVA du montant réellement encaissé.
     *
     * La TVA est dérivée ligne à ligne depuis `products.tva_rate` par
     * `VatDeclarationService` — le même point de vérité que la Déclaration TVA
     * (ticket 14.7), jamais un second calcul qui pourrait en diverger.
     *
     * ⚠️ REMISE : `sales.discount` réduit le montant encaissé sans être ventilé
     * par ligne. Elle est donc répartie PROPORTIONNELLEMENT sur le HT et la
     * TVA, de sorte que l'écriture équilibre exactement sur `sale->total`.
     * L'alternative — un compte de rabais dédié (709) — exigerait un compte
     * absent du plan comptable semé.
     *
     * @return array{0: float, 1: float}
     */
    private function ventilerHtEtTva(Sale $sale): array
    {
        $service = app(VatDeclarationService::class);

        // Ticket DEV3 — la facture d'un devis est une prestation libre : AUCUNE ligne, donc aucun produit qui porte un
        // taux. La TVA est celle du devis (neutralisée si l'exploitation n'est pas assujettie, comme pour un produit) ;
        // le total de la vente est TTC, comme `manual_total_amount`.
        if ($sale->lines->isEmpty() && $sale->devis) {
            $taux = app(TvaSettingService::class)->tauxPour((float) $sale->devis->tva_rate) / 100;
            $total = round((float) $sale->total, 2);
            $tva = $service->tva($total, $taux);

            return [round($total - $tva, 2), $tva];
        }

        $ht = 0.0;
        $tva = 0.0;
        $ttcLignes = 0.0;

        foreach ($sale->lines as $ligne) {
            $ttc = (float) ($ligne->manual_total_amount ?: ($ligne->qty * $ligne->unit_price));
            // Ticket 14.38 : aucune TVA ventilée si l'exploitation n'est pas
            // assujettie — la totalité va au compte de produit ou de charge.
            $taux = app(TvaSettingService::class)->tauxPour((float) ($ligne->product->tva_rate ?? 0)) / 100;

            $ttcLignes += $ttc;
            $ht += $service->ht($ttc, $taux);
            $tva += $service->tva($ttc, $taux);
        }

        $total = round((float) $sale->total, 2);

        // Sans remise, les lignes couvrent déjà exactement le total.
        if ($ttcLignes > 0 && abs($ttcLignes - $total) >= 0.01) {
            $ratio = $total / $ttcLignes;
            $ht = round($ht * $ratio, 2);
            $tva = round($tva * $ratio, 2);
        }

        // L'équilibre prime : le HT absorbe l'arrondi résiduel pour que
        // débit et crédit coïncident au centime — une écriture déséquilibrée
        // serait refusée par `AccountingEntryService` et ferait échouer la vente.
        $ht = round($total - $tva, 2);

        return [$ht, $tva];
    }
}
