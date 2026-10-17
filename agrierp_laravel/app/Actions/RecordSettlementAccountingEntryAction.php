<?php

namespace App\Actions;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\TreasuryAccount;
use App\Services\AccountingEntryService;

/**
 * Ticket 14.34 (Sprint 14) — ÉCRITURE COMPTABLE DES RÈGLEMENTS.
 *
 * 🔴 DÉFAUT TROUVÉ EN SIMULANT L'EXPLOITATION (ticket 14.31) : encaisser une
 * créance ou payer un fournisseur déplaçait l'argent dans la table
 * `treasury_accounts` **sans jamais l'inscrire au grand livre**.
 *
 * Conséquences, toutes vérifiables sur les états :
 *   - **411 Clients restait débité après paiement.** Le Bilan portait
 *     indéfiniment des créances encaissées, et la Balance Générale un solde
 *     client qui ne se soldait jamais.
 *   - **401 Fournisseurs restait crédité après règlement**, gonflant les
 *     dettes du passif.
 *   - Les comptes de trésorerie du grand livre (531, 521101, 521201) ne
 *     voyaient jamais ces mouvements : le **Rapprochement Bancaire** ne
 *     pouvait pas aboutir, et le Bilan sous-évaluait la trésorerie du montant
 *     de tous les règlements de la période.
 *
 * ⚠️ LE CDC L'EXIGE, §2 : « Solde de chaque compte recalculé en temps réel à
 * chaque vente/dépense/**règlement** validé ». Le règlement y figure au même
 * titre que la vente et la dépense.
 *
 * ÉCRITURES PRODUITES (SYSCOHADA) :
 *     Encaissement client   Débit trésorerie / Crédit 411 Clients
 *     Règlement fournisseur Débit 401 Fournisseurs / Crédit trésorerie
 *
 * ⚠️ UNE SEULE ÉCRITURE PAR RÈGLEMENT, même quand il solde plusieurs créances
 * en FIFO. Un versement est un fait comptable unique ; en produire une par
 * créance apurée multiplierait les écritures sans rien apprendre, et le
 * rapprochement bancaire chercherait plusieurs lignes là où le relevé n'en
 * porte qu'une.
 *
 * ⚠️ AUCUNE ÉCRITURE POUR UN MONTANT NUL : un règlement qui n'apure rien
 * (créance déjà soldée) ne doit pas laisser d'écriture à zéro au journal.
 */
class RecordSettlementAccountingEntryAction
{
    /**
     * Encaissement d'une créance client.
     *
     * @param  string|null  $sourceId  créance visée, si le règlement en cible une seule
     */
    public function collectFromCustomer(
        TreasuryAccount $tresorerie,
        float $montant,
        ?string $libelle = null,
        ?string $sourceId = null,
        ?string $date = null,
    ): ?AccountingEntry {
        return $this->enregistrer(
            tresorerie: $tresorerie,
            compteTiersCode: '411',
            montant: $montant,
            tresorerieAuDebit: true,
            libelle: 'Encaissement client'.($libelle ? ' — '.$libelle : ''),
            sourceType: 'receivable_settlement',
            sourceId: $sourceId,
            date: $date,
        );
    }

    /** Règlement d'une dette fournisseur. */
    public function payToSupplier(
        TreasuryAccount $tresorerie,
        float $montant,
        ?string $libelle = null,
        ?string $sourceId = null,
        ?string $date = null,
    ): ?AccountingEntry {
        return $this->enregistrer(
            tresorerie: $tresorerie,
            compteTiersCode: '401',
            montant: $montant,
            tresorerieAuDebit: false,
            libelle: 'Règlement fournisseur'.($libelle ? ' — '.$libelle : ''),
            sourceType: 'payable_settlement',
            sourceId: $sourceId,
            date: $date,
        );
    }

    /**
     * Ticket 15.19 (D2) — RÉCEPTION D'UNE AVANCE CLIENT : Débit trésorerie / Crédit 419.
     *
     * ⚠️ Une avance reçue n'est PAS un produit : c'est une dette envers le client (il faudra
     * livrer ou rembourser). Elle se crédite donc en 419, jamais en 701 ni en 411. Datée du jour de
     * l'ENCAISSEMENT (la date de l'avance), jamais de sa saisie.
     *
     * ⚠️ PROPOSITION À FAIRE VALIDER PAR LE CABINET FAGUEZ (compte 419 et schéma).
     */
    public function receiveCustomerAdvance(
        TreasuryAccount $tresorerie,
        float $montant,
        ?string $libelle = null,
        ?string $sourceId = null,
        ?string $date = null,
    ): ?AccountingEntry {
        return $this->enregistrer(
            tresorerie: $tresorerie,
            compteTiersCode: '419',
            montant: $montant,
            tresorerieAuDebit: true,
            libelle: 'Avance client'.($libelle ? ' — '.$libelle : ''),
            sourceType: 'customer_advance',
            sourceId: $sourceId,
            date: $date,
        );
    }

    /**
     * Ticket 15.20 (D8) — REMBOURSEMENT REÇU D'UN FOURNISSEUR : Débit trésorerie / Crédit 409.
     *
     * ⚠️ Le fournisseur rend l'argent d'un achat retourné : la créance qu'on avait sur lui (409, ouverte par la
     * contre-passation du retour) s'éteint contre l'entrée en caisse. Daté du jour de l'ENCAISSEMENT.
     * Aucune écriture pour un montant nul.
     *
     * ⚠️ PROPOSITION À FAIRE VALIDER PAR LE CABINET FAGUEZ (compte 409 et schéma).
     */
    public function receiveSupplierRefund(
        TreasuryAccount $tresorerie,
        float $montant,
        ?string $libelle = null,
        ?string $sourceId = null,
        ?string $date = null,
    ): ?AccountingEntry {
        return $this->enregistrer(
            tresorerie: $tresorerie,
            compteTiersCode: '409',
            montant: $montant,
            tresorerieAuDebit: true,
            libelle: 'Remboursement fournisseur'.($libelle ? ' — '.$libelle : ''),
            sourceType: 'supplier_refund',
            sourceId: $sourceId,
            date: $date,
        );
    }

    /**
     * Ticket 15.19 (D3) — IMPUTATION D'UNE AVANCE SUR UNE CRÉANCE : Débit 419 / Crédit 411,
     * SANS TRÉSORERIE. L'argent est entré à la réception de l'avance ; l'imputer ne le fait ni
     * entrer ni sortir, elle éteint seulement la dette envers le client (419) et la créance (411).
     *
     * ⚠️ AUCUNE ÉCRITURE POUR UN MONTANT NUL (même règle que les règlements). Datée de
     * l'imputation, jamais de la facture ni de l'avance d'origine.
     *
     * ⚠️ PROPOSITION À FAIRE VALIDER PAR LE CABINET FAGUEZ.
     */
    public function applyCustomerAdvance(
        float $montant,
        ?string $libelle = null,
        ?string $sourceId = null,
        ?string $date = null,
    ): ?AccountingEntry {
        $montant = round($montant, 2);

        if ($montant <= 0) {
            return null;
        }

        $avances = ChartOfAccount::where('code', '419')->first();
        $clients = ChartOfAccount::where('code', '411')->first();

        if (! $avances || ! $clients) {
            return null;   // plan comptable incomplet — signalé, jamais deviné
        }

        return app(AccountingEntryService::class)->record(
            lines: [
                ['account_id' => $avances->id, 'debit' => $montant, 'credit' => 0],
                ['account_id' => $clients->id, 'debit' => 0, 'credit' => $montant],
            ],
            entryDate: $date ?? now()->format('Y-m-d'),
            reference: mb_substr(AccountingEntry::generateReference().' — Imputation d\'avance client'.($libelle ? ' — '.$libelle : ''), 0, 100),
            sourceType: 'advance_imputation',
            sourceId: $sourceId,
        );
    }

    private function enregistrer(
        TreasuryAccount $tresorerie,
        string $compteTiersCode,
        float $montant,
        bool $tresorerieAuDebit,
        string $libelle,
        string $sourceType,
        ?string $sourceId,
        ?string $date,
    ): ?AccountingEntry {
        $montant = round($montant, 2);

        if ($montant <= 0) {
            return null;
        }

        $compteTresorerie = $tresorerie->account_code
            ? ChartOfAccount::where('code', $tresorerie->account_code)->first()
            : null;

        $compteTiers = ChartOfAccount::where('code', $compteTiersCode)->first();

        if (! $compteTresorerie || ! $compteTiers) {
            return null;   // plan comptable incomplet — signalé, jamais deviné
        }

        $lignes = $tresorerieAuDebit
            ? [
                ['account_id' => $compteTresorerie->id, 'debit' => $montant, 'credit' => 0],
                ['account_id' => $compteTiers->id, 'debit' => 0, 'credit' => $montant],
            ]
            : [
                ['account_id' => $compteTiers->id, 'debit' => $montant, 'credit' => 0],
                ['account_id' => $compteTresorerie->id, 'debit' => 0, 'credit' => $montant],
            ];

        return app(AccountingEntryService::class)->record(
            lines: $lignes,
            // Datée du RÈGLEMENT, jamais de la facture d'origine : c'est
            // l'encaissement qui est le fait comptable ici, et antidater
            // rouvrirait une période souvent déjà déclarée.
            entryDate: $date ?? now()->format('Y-m-d'),
            // ⚠️ `reference` est un varchar(100) : un nom de tiers long ferait échouer l'écriture
            // (et toute l'opération avec elle) sur MySQL. Tronqué explicitement (ticket 15.19).
            reference: mb_substr(AccountingEntry::generateReference().' — '.$libelle, 0, 100),
            sourceType: $sourceType,
            sourceId: $sourceId,
        );
    }
}
