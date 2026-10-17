<?php

namespace App\Actions;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FixedAsset;
use App\Models\TreasuryAccount;
use App\Services\AccountingEntryService;

/**
 * Ticket 14.26 (Sprint 14) — CAPITALISATION D'UNE IMMOBILISATION.
 *
 * ÉCRITURE PRODUITE (SYSCOHADA) :
 *     Débit  2xx (221/241/244) ..... valeur d'acquisition
 *     Crédit contrepartie .......... trésorerie qui paie, ou 401 si à crédit
 *
 * ⚠️ SANS CETTE ÉCRITURE, LE BILAN AFFICHERAIT UN ACTIF IMMOBILISÉ NÉGATIF.
 * `FinancialReportService::bilan()` somme toute la classe 2, amortissements
 * 281 compris — formule juste (VNC = brut − amortissement) à condition que le
 * brut existe au grand livre. Aucun flux ne débitait 221/241/244 : les achats
 * passent en charges (601). Une dotation seule aurait donc crédité 281 face à
 * un brut nul.
 *
 * ⚠️ UN BIEN N'EST JAMAIS CAPITALISÉ DEUX FOIS — `acquisition_entry_id`
 * garde la porte, comme `accounting_entry_id` le fait pour les ventes (14.23),
 * les achats (14.24) et la paie (14.25).
 *
 * ⚠️ AUCUNE ÉCRITURE POUR UNE REPRISE D'ANTÉRIORITÉ. Un bien déjà en service
 * avant la mise en route de l'ERP n'a pas été payé pendant l'exercice :
 * inventer une contrepartie de trésorerie fabriquerait un décaissement qui
 * n'a jamais eu lieu, et une contrepartie au Capital falsifierait les capitaux
 * propres. Ces biens restent hors comptabilité, signalés comme tels à l'écran,
 * jusqu'à ce que le projet se dote d'un vrai bilan d'ouverture.
 */
class RecordAssetAcquisitionEntryAction
{
    /**
     * @param  string|null  $treasuryAccountId  compte de trésorerie qui paie ;
     *                                          null ⇒ acquisition à crédit (401)
     * @return AccountingEntry|null             null si déjà capitalisé ou plan
     *                                          comptable incomplet
     */
    public function execute(FixedAsset $asset, ?string $treasuryAccountId): ?AccountingEntry
    {
        if ($asset->acquisition_entry_id !== null) {
            return null;
        }

        $compteBien = ChartOfAccount::where('code', $asset->account_code)->first();
        $contrepartie = $this->contrepartie($treasuryAccountId);

        if (! $compteBien || ! $contrepartie) {
            return null;   // plan comptable incomplet — signalé, jamais deviné
        }

        $valeur = round((float) $asset->acquisition_value, 2);

        if ($valeur <= 0) {
            return null;
        }

        $entry = app(AccountingEntryService::class)->record(
            lines: [
                ['account_id' => $compteBien->id, 'debit' => $valeur, 'credit' => 0],
                ['account_id' => $contrepartie->id, 'debit' => 0, 'credit' => $valeur],
            ],
            // Datée de l'ACQUISITION RÉELLE, pas du jour de la saisie : un bien
            // acquis le mois dernier et enregistré aujourd'hui doit figurer à
            // l'actif de la période où il est réellement entré.
            entryDate: $asset->acquisition_date->format('Y-m-d'),
            reference: AccountingEntry::generateReference().' — Acquisition '.$asset->code,
            sourceType: 'asset_acquisition',
            sourceId: $asset->id,
        );

        $asset->update(['acquisition_entry_id' => $entry->id, 'is_capitalized' => true]);

        return $entry;
    }

    /**
     * REPRISE D'ANTÉRIORITÉ : un bien déjà possédé entre à l'actif par apport
     * en CAPITAL, jamais par une dette ni un décaissement.
     *
     *     Débit  2xx (le bien) ........ valeur d'acquisition
     *     Crédit 101 Capital social ... même montant
     *
     * ⚠️ C'EST LA LIMITE DU TICKET 14.26 QUI TOMBE ICI. Ce bien n'a été ni
     * payé ni acheté à crédit pendant l'exercice : lui donner une contrepartie
     * de trésorerie fabriquerait un décaissement qui n'a jamais eu lieu, et une
     * contrepartie fournisseur une dette que personne ne réclamera — c'est
     * exactement ce qu'a produit la simulation avant cette méthode : 3 870 000
     * FCFA de dettes fournisseurs fantômes, que le règlement automatique
     * s'est ensuite employé à « payer », vidant la trésorerie de la ferme.
     *
     * La contrepartie juste est le capital : la ferme possède ce bien parce
     * qu'il a été apporté. Le compte 101 manquait au plan comptable, il y est
     * désormais.
     */
    public function recordOpeningContribution(FixedAsset $asset, ?string $date = null): ?AccountingEntry
    {
        if ($asset->acquisition_entry_id !== null) {
            return null;
        }

        $compteBien = ChartOfAccount::where('code', $asset->account_code)->first();
        $capital = ChartOfAccount::where('code', '101')->first();
        $valeur = round((float) $asset->acquisition_value, 2);

        if (! $compteBien || ! $capital || $valeur <= 0) {
            return null;
        }

        $entry = app(AccountingEntryService::class)->record(
            lines: [
                ['account_id' => $compteBien->id, 'debit' => $valeur, 'credit' => 0],
                ['account_id' => $capital->id, 'debit' => 0, 'credit' => $valeur],
            ],
            entryDate: $date ?? $asset->acquisition_date->format('Y-m-d'),
            reference: AccountingEntry::generateReference().' — Apport '.$asset->code,
            sourceType: 'asset_opening',
            sourceId: $asset->id,
        );

        $asset->update(['acquisition_entry_id' => $entry->id, 'is_capitalized' => true]);

        return $entry;
    }

    /** Trésorerie choisie, ou dette fournisseur (401) si acquisition à crédit. */
    private function contrepartie(?string $treasuryAccountId): ?ChartOfAccount
    {
        if ($treasuryAccountId === null || $treasuryAccountId === '') {
            return ChartOfAccount::where('code', '401')->first();
        }

        $tresorerie = TreasuryAccount::find($treasuryAccountId);

        if (! $tresorerie || ! $tresorerie->account_code) {
            return null;
        }

        return ChartOfAccount::where('code', $tresorerie->account_code)->first();
    }
}
