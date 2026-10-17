<?php

namespace App\Actions;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\TreasuryAccount;
use App\Services\AccountingEntryService;
use Illuminate\Support\Facades\DB;

/**
 * Ticket 14.35 (Sprint 14) — VIREMENT INTERNE entre comptes de trésorerie.
 *
 * 🔴 FONCTION ABSENTE, révélée par la simulation (ticket 14.31) : l'application
 * n'offrait AUCUN moyen de déplacer de l'argent d'un compte à un autre. Chaque
 * compte vivait isolé de ses seules recettes propres.
 *
 * Ce n'est pas une commodité. Cette exploitation encaisse l'essentiel de ses
 * ventes en ESPÈCES et par MOBILE MONEY, mais règle ses gros postes — provende,
 * poussins, équipement — par la banque. Sans dépôt possible en banque, le
 * compte bancaire se vide mécaniquement pendant que la caisse déborde. La
 * simulation l'a montré dans les trois sens : banque à −3,3 M, puis caisse à
 * −262 000, puis Mobile Money à −1,6 M, selon le compte qu'on faisait payer.
 * Aucune règle d'allocation ne peut corriger cela — il manquait le virement.
 *
 * ÉCRITURE PRODUITE (SYSCOHADA) :
 *     Débit  compte de classe 5 destinataire ..... montant viré
 *     Crédit compte de classe 5 source .......... même montant
 *
 * ⚠️ NI PRODUIT NI CHARGE. Un virement interne ne touche aucun compte de
 * classe 6 ou 7 : l'argent change de poche, la richesse de l'exploitation est
 * inchangée. Le Compte de Résultat ne doit rien en voir, et le total de
 * trésorerie du Bilan reste identique avant et après.
 *
 * ⚠️ BLOCAGE STRICT SI LES FONDS MANQUENT — et c'est délibérément l'inverse de
 * la règle retenue pour le stock (ticket 14.30, alerte non bloquante). La
 * différence est réelle : une vente en rupture constate un fait déjà accompli
 * (le produit est dans les mains du client), tandis qu'un virement est un acte
 * purement interne, que rien n'oblige à enregistrer. On ne vire pas un argent
 * qu'on n'a pas.
 */
class RecordTreasuryTransferAction
{
    /**
     * @throws \InvalidArgumentException  si les comptes sont identiques, si le
     *                                    montant est nul, ou si la source est
     *                                    insuffisamment provisionnée
     */
    public function execute(
        TreasuryAccount $source,
        TreasuryAccount $destination,
        float $montant,
        ?string $motif = null,
        ?string $date = null,
    ): ?AccountingEntry {
        $montant = round($montant, 2);

        if ($source->id === $destination->id) {
            throw new \InvalidArgumentException('Le compte source et le compte destinataire doivent être différents.');
        }

        if ($montant <= 0) {
            throw new \InvalidArgumentException('Le montant du virement doit être supérieur à zéro.');
        }

        if (round((float) $source->balance, 2) < $montant) {
            throw new \InvalidArgumentException(
                'Solde insuffisant sur '.$source->label.' : '
                .number_format((float) $source->balance, 0, ',', ' ').' FCFA disponibles.'
            );
        }

        $compteSource = $this->compteComptable($source);
        $compteDestination = $this->compteComptable($destination);

        if (! $compteSource || ! $compteDestination) {
            return null;   // plan comptable incomplet — signalé, jamais deviné
        }

        return DB::transaction(function () use (
            $source, $destination, $montant, $motif, $date, $compteSource, $compteDestination
        ) {
            // ⚠️ Les deux soldes bougent DANS LA MÊME TRANSACTION que
            // l'écriture : un virement à moitié appliqué ferait disparaître de
            // l'argent, l'anomalie la plus difficile à retrouver ensuite.
            $source->decrement('balance', $montant);
            $destination->increment('balance', $montant);

            return app(AccountingEntryService::class)->record(
                lines: [
                    ['account_id' => $compteDestination->id, 'debit' => $montant, 'credit' => 0],
                    ['account_id' => $compteSource->id, 'debit' => 0, 'credit' => $montant],
                ],
                entryDate: $date ?? now()->format('Y-m-d'),
                // ⚠️ RÉFÉRENCE TRONQUÉE À LA LONGUEUR DE LA COLONNE. Composée
                // du numéro, des deux libellés de comptes et du motif, elle
                // dépassait `accounting_entries.reference` dès que les libellés
                // étaient un peu longs — et l'écriture échouait alors sur une
                // erreur SQL brute, entraînant tout le virement avec elle.
                // Constaté en simulation, pas en théorie.
                reference: mb_substr(
                    AccountingEntry::generateReference().' — Virement '
                        .$source->label.' vers '.$destination->label
                        .($motif ? ' ('.$motif.')' : ''),
                    0, 100
                ),
                sourceType: 'treasury_transfer',
                sourceId: $destination->id,
            );
        });
    }

    private function compteComptable(TreasuryAccount $compte): ?ChartOfAccount
    {
        if (! $compte->account_code) {
            return null;
        }

        return ChartOfAccount::where('code', $compte->account_code)->first();
    }
}
