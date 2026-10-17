<?php

namespace App\Actions;

use App\Exceptions\ClosedFiscalYearException;
use App\Exceptions\NoOpenFiscalYearException;
use App\Exceptions\SaleDateRefusedException;
use App\Models\PeriodicClosure;
use App\Services\AccountingEntryService;
use Carbon\Carbon;
use DateTimeInterface;

/**
 * Ticket 15.30 — POINT DE PASSAGE UNIQUE : « cette date de vente est-elle
 * acceptable ? ». Appelé par `SyncController::pushSales` (vente reçue du poste)
 * et par `PosInterface::validateSale` (vente du comptoir web portant une date).
 *
 * Trois refus, décidés par le client le 14/10/2026 :
 *
 *  1. DATE FUTURE — une vente n'a pas pu avoir lieu demain ;
 *  2. MOIS CLÔTURÉ — décision à FAIRE CONFIRMER PAR LE CABINET FAGUEZ. Le
 *     verrou est celui du Journal Comptable : `PeriodicClosure::isDateLocked()`,
 *     jamais réimplémenté ici (deux textes d'une même règle finissent par
 *     diverger) ;
 *  3. EXERCICE ABSENT OU CLOS — `AccountingEntryService::exerciceOuvertPour()`,
 *     la règle même qui refuserait l'écriture. Contrôlé AVANT d'engager la
 *     vente : un mode de règlement qui ne produit pas d'écriture (« avance »)
 *     serait sinon accepté dans un exercice clos.
 *
 * ⚠️ AUCUNE RÈGLE COMPTABLE N'EST CRÉÉE ICI : l'action ne fait qu'appeler, avant
 * la vente, les contrôles que le Journal et le service comptable appliquent déjà.
 *
 * ⚠️ LA RÉMANENCE N'EST PAS UN MOTIF DE REFUS (décision client) : une vente
 * antérieure est ENREGISTRÉE et la rémanence SIGNALÉE
 * (`FlagSaleUnderWithdrawalAction`).
 */
class VerifySaleDateAction
{
    /**
     * @throws SaleDateRefusedException  message français, prêt à afficher
     */
    public function execute(DateTimeInterface|string $date): void
    {
        $instant = Carbon::parse($date);
        $jour = $instant->format('Y-m-d');
        $jourFr = $instant->format('d/m/Y');

        if ($instant->greaterThan(now())) {
            throw new SaleDateRefusedException("Vente refusée : la date du {$jourFr} est dans le futur.");
        }

        if (PeriodicClosure::isDateLocked($jour)) {
            throw new SaleDateRefusedException(
                "Vente refusée : le mois {$instant->format('Y-m')} est clôturé — aucune vente ne peut y être datée "
                .'(le Journal Comptable applique la même règle). Un Administrateur peut déclôturer ce mois exceptionnellement.'
            );
        }

        try {
            app(AccountingEntryService::class)->exerciceOuvertPour($jour);
        } catch (NoOpenFiscalYearException) {
            throw new SaleDateRefusedException(
                "Vente refusée : aucun exercice comptable ne couvre le {$jourFr}. Créez l'exercice avant d'enregistrer cette vente."
            );
        } catch (ClosedFiscalYearException) {
            throw new SaleDateRefusedException(
                "Vente refusée : l'exercice comptable qui couvre le {$jourFr} est clos. Aucune vente ne peut y être datée."
            );
        }
    }
}
