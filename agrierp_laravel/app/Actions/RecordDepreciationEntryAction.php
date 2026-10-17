<?php

namespace App\Actions;

use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\ChartOfAccount;
use App\Models\FixedAsset;
use App\Services\AccountingEntryService;

/**
 * Ticket 14.26 (Sprint 14) — DOTATION AUX AMORTISSEMENTS.
 *
 * ÉCRITURE PRODUITE (SYSCOHADA) :
 *     Débit  681 Dotations aux amortissements ....... dotation de la période
 *     Crédit 281 Amortissements des immobilisations . même montant
 *
 * ⚠️ LA DOTATION EST UN ÉCART, PAS UN CUMUL. Le montant porté est
 * « amortissement cumulé théorique à la date d'arrêté » MOINS « amortissement
 * déjà comptabilisé au crédit de 281 ». Recalculer et poster le cumul complet
 * à chaque passage doublerait la charge à la deuxième exécution — et rien
 * dans l'écran n'empêche un comptable de cliquer deux fois. Cette forme est
 * naturellement idempotente : relancée le même jour, elle ne trouve plus rien
 * à doter et ne produit aucune écriture.
 *
 * Elle est aussi AUTO-CORRECTRICE : si un bien est ajouté au registre après
 * coup, ou si une dotation d'un mois a été oubliée, l'écart la rattrape à la
 * dotation suivante — la comptabilité rejoint le registre sans reprise
 * manuelle.
 *
 * ⚠️ Le montant déjà comptabilisé se lit sur le GRAND LIVRE (solde créditeur
 * de 281), pas sur un champ « dernière dotation » stocké dans le registre. Le
 * grand livre est le seul point de vérité de ce qui est réellement
 * comptabilisé : un champ parallèle divergerait dès la première écriture
 * passée à la main au Journal Comptable.
 */
class RecordDepreciationEntryAction
{
    /**
     * @return AccountingEntry|null  null si rien n'est à doter (registre vide,
     *                               biens déjà totalement amortis, ou dotation
     *                               déjà passée) — jamais une écriture à zéro.
     */
    public function execute(string $dateArrete): ?AccountingEntry
    {
        $dotations = ChartOfAccount::where('code', '681')->first();
        $amortissements = ChartOfAccount::where('code', '281')->first();

        if (! $dotations || ! $amortissements) {
            return null;   // plan comptable incomplet — signalé, jamais deviné
        }

        $aDoter = round($this->cumulTheorique($dateArrete) - $this->dejaComptabilise($amortissements->id, $dateArrete), 2);

        if ($aDoter < 0.01) {
            return null;
        }

        return app(AccountingEntryService::class)->record(
            lines: [
                ['account_id' => $dotations->id, 'debit' => $aDoter, 'credit' => 0],
                ['account_id' => $amortissements->id, 'debit' => 0, 'credit' => $aDoter],
            ],
            entryDate: $dateArrete,
            reference: AccountingEntry::generateReference().' — Dotation amortissements au '.$dateArrete,
            sourceType: 'depreciation',
        );
    }

    /** Montant qui SERA doté si l'action est exécutée — pour affichage avant clic. */
    public function montantADoter(string $dateArrete): float
    {
        $amortissements = ChartOfAccount::where('code', '281')->first();

        if (! $amortissements) {
            return 0.0;
        }

        return round(max(0, $this->cumulTheorique($dateArrete) - $this->dejaComptabilise($amortissements->id, $dateArrete)), 2);
    }

    /**
     * Amortissement cumulé des biens RÉELLEMENT CAPITALISÉS à la date d'arrêté.
     *
     * ⚠️ Les reprises d'antériorité en sont exclues : elles ne sont jamais
     * entrées à l'actif (aucune écriture de classe 2), donc les amortir
     * créerait une charge sans l'actif en face — l'Actif Immobilisé du Bilan
     * deviendrait négatif du montant de leur amortissement. Leur valeur relève
     * d'un bilan d'ouverture que ce projet n'importe pas encore.
     */
    private function cumulTheorique(string $dateArrete): float
    {
        return round(
            FixedAsset::active()->capitalized()->get()->sum(fn (FixedAsset $bien) => $bien->cumulAmortissement($dateArrete)),
            2
        );
    }

    /**
     * Solde créditeur de 281 à la date d'arrêté.
     *
     * Débits déduits : une reprise d'amortissement (cession d'un bien) débite
     * 281 et doit bien diminuer le cumul déjà comptabilisé, sinon la dotation
     * suivante serait sous-estimée du montant de la reprise.
     */
    private function dejaComptabilise(string $accountId, string $dateArrete): float
    {
        $lignes = AccountingEntryLine::where('account_id', $accountId)
            ->whereHas('entry', function ($q) use ($dateArrete) {
                $q->where('is_active', true)->whereDate('entry_date', '<=', $dateArrete);
            });

        return round((float) (clone $lignes)->sum('credit') - (float) $lignes->sum('debit'), 2);
    }
}
