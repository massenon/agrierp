<?php

namespace App\Actions;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\Payslip;
use App\Models\TreasuryAccount;
use App\Services\AccountingEntryService;

/**
 * Ticket 14.25 (Sprint 14) — ÉCRITURE COMPTABLE AUTOMATIQUE DE LA PAIE.
 *
 * Dernier des trois flux financiers cités par le CDC (« vente, achat, paie,
 * perte ») à ne produire aucune écriture. Après les ventes (14.23) et les
 * achats (14.24), la boucle comptable se ferme ici.
 *
 * ÉCRITURE PRODUITE (SYSCOHADA) :
 *     Débit  661 Charges de personnel ......... salaire réellement dû
 *     Crédit 431 Sécurité sociale (CNSS) ...... retenue salariale
 *     Crédit compte de trésorerie ............. net effectivement versé
 *
 * ⚠️ LA CHARGE EST LE SALAIRE DÛ, PAS LE NET VERSÉ. La retenue CNSS est
 * prélevée SUR le salarié mais reste due à l'organisme : la comptabiliser
 * comme une dette (431) et non comme une non-dépense est ce qui distingue une
 * écriture juste d'une écriture qui équilibre par hasard. Comptabiliser le
 * seul net sous-estimerait les charges de personnel de 3,6 % chaque mois.
 *
 * ⚠️ L'ABSENCE réduit le salaire réellement dû — ce n'est pas une retenue à
 * reverser à un tiers, donc elle n'a pas de compte de contrepartie : elle
 * diminue simplement la charge. `brut − déduction d'absence` est donc le
 * montant porté au débit de 661.
 */
class RecordPayrollAccountingEntryAction
{
    /**
     * @return AccountingEntry|null  null si l'écriture n'a pas pu être générée
     *                               — l'appelant DOIT alors avertir.
     */
    public function execute(Payslip $payslip, ?string $treasuryAccountId = null, ?string $dateCharge = null, ?string $dateReglement = null): ?AccountingEntry
    {
        if ($payslip->accounting_entry_id !== null) {
            return null;   // déjà comptabilisée — jamais de doublon
        }

        $personnel = ChartOfAccount::where('code', '661')->first();

        if (! $personnel) {
            return null;   // plan comptable incomplet — signalé, jamais deviné
        }

        $net = round((float) $payslip->net_salary, 2);
        $cnss = round((float) $payslip->cnss_deduction, 2);
        $its = round((float) ($payslip->its_deduction ?? 0), 2);

        // Salaire réellement dû = ce que le salarié coûte en salaire, avant
        // toute retenue : net + CNSS salariale + ITS.
        $charge = round($net + $cnss + $its, 2);

        if ($charge <= 0) {
            return null;
        }

        $lignes = [
            ['account_id' => $personnel->id, 'debit' => $charge, 'credit' => 0],
        ];

        // 🔴→✅ TICKET 14.38 — RETENUE D'IMPÔT (ITS).
        //
        // ⚠️ MÊME NATURE QUE LA CNSS SALARIALE : prélevée SUR le salarié mais
        // due au Trésor. C'est une DETTE de l'entreprise (4472), pas une
        // moindre charge. L'omettre sous-estimait les charges de personnel du
        // montant de l'impôt retenu, exactement comme le faisait l'omission de
        // la CNSS avant le ticket 14.25.
        if ($its > 0) {
            $compteIts = ChartOfAccount::where('code', '4472')->first();

            if (! $compteIts) {
                return null;
            }

            $lignes[] = ['account_id' => $compteIts->id, 'debit' => 0, 'credit' => $its];
        }

        // 🔴→✅ TICKET 14.38 — CHARGES PATRONALES.
        //
        // ⚠️ ELLES NE TOUCHENT PAS LE NET DU SALARIÉ. VPS et CNSS employeur
        // sont versées EN PLUS par l'entreprise : elles augmentent la charge
        // (664) et créent une dette envers l'organisme, sans rien retirer au
        // salarié. Les traiter comme des retenues aurait amputé le net ; les
        // omettre — ce que faisait l'application — sous-déclarait le coût réel
        // du travail de près de 21 % du salaire dû.
        $vps = round((float) ($payslip->vps_employer ?? 0), 2);
        $cnssPatronale = round(
            (float) ($payslip->cnss_employer_pension ?? 0)
            + (float) ($payslip->cnss_employer_family ?? 0)
            + (float) ($payslip->cnss_employer_risk ?? 0),
            2
        );

        if ($vps > 0 || $cnssPatronale > 0) {
            $chargesSociales = ChartOfAccount::where('code', '664')->first();

            if (! $chargesSociales) {
                return null;
            }

            $lignes[] = ['account_id' => $chargesSociales->id, 'debit' => round($vps + $cnssPatronale, 2), 'credit' => 0];

            if ($vps > 0) {
                $compteVps = ChartOfAccount::where('code', '4473')->first();

                if (! $compteVps) {
                    return null;
                }

                $lignes[] = ['account_id' => $compteVps->id, 'debit' => 0, 'credit' => $vps];
            }
        }

        // ⚠️ UNE SEULE LIGNE PAR COMPTE. Les parts salariale et patronale de la
        // CNSS sont dues au MÊME organisme : les porter sur deux lignes
        // distinctes de la même écriture serait légal mais illisible au grand
        // livre, et masquerait le montant réellement dû à la CNSS pour le mois.
        // C'est la somme qui part à l'organisme, c'est elle qu'on inscrit.
        $cnssTotale = round($cnss + $cnssPatronale, 2);

        if ($cnssTotale > 0) {
            $securiteSociale = ChartOfAccount::where('code', '431')->first();

            if (! $securiteSociale) {
                return null;
            }

            $lignes[] = ['account_id' => $securiteSociale->id, 'debit' => 0, 'credit' => $cnssTotale];
        }

        $compteTresorerie = $this->compteDeTresorerie($treasuryAccountId);

        if (! $compteTresorerie) {
            return null;
        }

        $dateReglement ??= now()->format('Y-m-d');
        $dateCharge ??= $dateReglement;
        $reference = AccountingEntry::generateReference().' — Paie '.($payslip->period_month?->format('m/Y') ?? '');

        // 🔴→✅ TICKET EX5 (décision Q4 du 20/10/2026) — CHARGE ET RÈGLEMENT À DEUX DATES. La paie de décembre N réglée en
        // janvier N+1 : la charge appartient à N (datée du 31/12/N), le décaissement à N+1 (à sa date). Une seule
        // écriture ne peut porter qu'une date — elle aurait fait sortir la caisse au 31/12 (rapprochement faux) ou passé
        // la charge en N+1. Deux écritures, par le compte 422 « Personnel, rémunérations dues » (plan SYSCOHADA importé,
        // 15.27) : charge D 661/664 — C 431/4472/4473/422 ; règlement D 422 — C trésorerie. Le cas courant (paie réglée
        // le jour où sa charge est datée) garde l'écriture unique ci-dessous, inchangée.
        if ($dateCharge !== $dateReglement) {
            $remunerationsDues = ChartOfAccount::where('code', '422')->first();

            if (! $remunerationsDues) {
                return null;   // plan comptable incomplet — signalé par l'appelant, jamais un compte inventé
            }

            $service = app(AccountingEntryService::class);
            $entry = $service->record(
                lines: [...$lignes, ['account_id' => $remunerationsDues->id, 'debit' => 0, 'credit' => $net]],
                entryDate: $dateCharge,
                reference: $reference,
                sourceType: 'payroll',
                sourceId: $payslip->id,
            );
            $service->record(
                lines: [
                    ['account_id' => $remunerationsDues->id, 'debit' => $net, 'credit' => 0],
                    ['account_id' => $compteTresorerie->id, 'debit' => 0, 'credit' => $net],
                ],
                entryDate: $dateReglement,
                reference: mb_substr($reference.' — règlement', 0, 100),
                sourceType: 'payroll_payment',
                sourceId: $payslip->id,
            );

            $payslip->update(['accounting_entry_id' => $entry->id]);

            return $entry;
        }

        $lignes[] = ['account_id' => $compteTresorerie->id, 'debit' => 0, 'credit' => $net];

        $entry = app(AccountingEntryService::class)->record(
            lines: $lignes,
            // ⚠️ DATÉE DU RÈGLEMENT, PAS DE LA FIN DE PÉRIODE. Cette écriture
            // combine la CHARGE et son PAIEMENT en un seul mouvement : la dater
            // de la fin du mois de paie la désynchroniserait du décaissement
            // réel — le solde de trésorerie du grand livre ne suivrait plus
            // celui du compte, et une paie réglée en cours de mois
            // n'apparaîtrait pas dans les états arrêtés à ce jour (défaut
            // constaté au test avant correction).
            //
            // Quand la charge appartient à une autre date que le règlement (paie
            // d'un mois passé, Q4), les DEUX écritures par le compte 422 sont
            // passées plus haut (ticket EX5) ; ici, charge et règlement le même jour.
            entryDate: $dateReglement,
            reference: $reference,
            sourceType: 'payroll',
            sourceId: $payslip->id,
        );

        $payslip->update(['accounting_entry_id' => $entry->id]);

        return $entry;
    }

    /**
     * Compte comptable du compte de trésorerie qui règle la paie.
     *
     * ⚠️ À défaut de sélection explicite, le premier compte actif est retenu —
     * c'est exactement ce que fait déjà `GestionPaie` pour décrémenter le
     * solde. Reproduire ici une seconde règle de choix ferait diverger
     * l'écriture du mouvement de trésorerie réel. Le fait que cet écran ne
     * demande PAS quel compte paie est une limite de l'écran, signalée comme
     * telle, pas quelque chose à corriger en douce dans une Action comptable.
     */
    private function compteDeTresorerie(?string $treasuryAccountId): ?ChartOfAccount
    {
        $tresorerie = $treasuryAccountId
            ? TreasuryAccount::find($treasuryAccountId)
            : TreasuryAccount::where('is_active', true)->first();

        if (! $tresorerie || ! $tresorerie->account_code) {
            return null;
        }

        return ChartOfAccount::where('code', $tresorerie->account_code)->first();
    }
}
