<?php

namespace App\Services;

use App\Exceptions\ClosedFiscalYearException;
use App\Exceptions\NoOpenFiscalYearException;
use App\Exceptions\UnbalancedAccountingEntryException;
use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\FiscalYear;
use Illuminate\Support\Facades\DB;

/**
 * Ticket 10.2 (Sprint 10) — POINT DE PASSAGE UNIQUE pour toute écriture
 * comptable (Document 02 §Services, Document 03 §Contraintes
 * applicatives). Aucun module (POS, Achats, Paie, Journal manuel...) ne
 * doit jamais créer directement une `AccountingEntry`/`AccountingEntryLine`
 * — toujours via ce service, jamais par un `Model::create()` isolé
 * ailleurs qui pourrait un jour oublier la contrainte d'équilibre.
 *
 * ⚠️ CONTRAINTE CRITIQUE, VÉRIFIÉE AVANT TOUT `save()` : la somme des
 * débits DOIT être rigoureusement égale à la somme des crédits. Toute
 * tentative de créer une écriture déséquilibrée est refusée avant
 * d'atteindre la base — `UnbalancedAccountingEntryException` levée,
 * aucune ligne partielle jamais persistée (comparaison avec arrondi au
 * centime pour absorber les imprécisions flottantes légitimes, jamais un
 * seuil plus large qui masquerait un vrai déséquilibre).
 *
 * Ce service NE COUVRE PAS la contrainte additionnelle "compte débité ≠
 * compte crédité" (Document 01 §6.3) — cette règle est spécifique à la
 * SAISIE MANUELLE au Journal Comptable (ticket 10.4, formulaire à 2
 * lignes explicites), pas à toute écriture générée automatiquement
 * (une écriture de vente multi-lignes peut légitimement toucher
 * plusieurs comptes de produits différents crédités face à un seul
 * compte de trésorerie débité — la contrainte "comptes distincts" n'a de
 * sens que pour une saisie manuelle à 2 lignes). Le composant du ticket
 * 10.4 devra appliquer cette vérification supplémentaire lui-même, en
 * plus de (jamais à la place de) l'équilibre vérifié ici.
 *
 * RETROCÂBLAGE DES MODULES EXISTANTS (POS, Achats, Paie, Dépenses...)
 * DÉLIBÉRÉMENT HORS PÉRIMÈTRE DE CE TICKET : chaque intégration
 * nécessite une décision de mapping SYSCOHADA propre à son type de
 * transaction (ex. vente → 531/701, achat → 601/401...) — ce travail
 * arrive progressivement à mesure que les écrans comptables eux-mêmes
 * sont construits (tickets 10.3 à 10.8), pas en un seul geste ici.
 * Documenté explicitement pour ne jamais être oublié en aval.
 */
class AccountingEntryService
{
    /**
     * Ticket 15.30 — L'exercice OUVERT qui couvre `$entryDate`, ou une exception.
     *
     * Extrait de `record()` pour que la règle « exercice absent ou clos = refus »
     * ait UN SEUL texte : `record()` l'applique à chaque écriture, et
     * `VerifySaleDateAction` l'interroge AVANT d'engager une vente datée (le
     * refus vient alors avant tout effet de bord, y compris pour un mode de
     * règlement qui ne produit aucune écriture).
     *
     * @throws NoOpenFiscalYearException  aucun exercice ne couvre la date
     * @throws ClosedFiscalYearException  l'exercice qui la couvre est clos
     */
    public function exerciceOuvertPour(string $entryDate): FiscalYear
    {
        $fiscalYear = FiscalYear::whereDate('start_date', '<=', $entryDate)
            ->whereDate('end_date', '>=', $entryDate)
            ->first();

        if (! $fiscalYear) {
            throw new NoOpenFiscalYearException();
        }

        if ($fiscalYear->status !== 'ouvert') {
            throw ClosedFiscalYearException::forDate($entryDate);
        }

        return $fiscalYear;
    }

    /**
     * @param  array<int, array{account_id: string, cost_center_id?: ?string, debit?: float, credit?: float}>  $lines
     */
    public function record(
        array $lines,
        string $entryDate,
        ?string $reference = null,
        ?string $sourceType = null,
        ?string $sourceId = null,
    ): AccountingEntry {
        $totalDebit = round(array_sum(array_column($lines, 'debit')), 2);
        $totalCredit = round(array_sum(array_column($lines, 'credit')), 2);

        // Comparaison au centime près — absorbe les imprécisions flottantes
        // légitimes, jamais un seuil plus large qui masquerait un vrai écart.
        if (abs($totalDebit - $totalCredit) >= 0.01) {
            throw UnbalancedAccountingEntryException::forTotals($totalDebit, $totalCredit);
        }

        // ⚠️ Ticket 10.6 : résout l'exercice qui COUVRE RÉELLEMENT la date de
        // l'écriture (pas "le dernier exercice ouvert" appliqué aveuglément) —
        // sans cette correction, une écriture antidatée dans un exercice
        // désormais clos aurait pu être rattachée à tort au nouvel exercice
        // ouvert. Document 01 §6.6 point 4 : blocage serveur systématique.
        $fiscalYear = $this->exerciceOuvertPour($entryDate);

        return DB::transaction(function () use ($lines, $entryDate, $reference, $sourceType, $sourceId, $fiscalYear) {
            // Ticket 15.20a : le numéro est attribué ICI, dans la transaction et sous verrou, jamais
            // avant. Une référence saisie à la main (sans gabarit) est conservée telle quelle.
            if ($reference !== null && str_contains($reference, AccountingEntry::GABARIT_NUMERO)) {
                $reference = mb_substr(
                    preg_replace('/'.preg_quote(AccountingEntry::GABARIT_NUMERO, '/').'/', AccountingEntry::attribuerNumero($fiscalYear), $reference, 1),
                    0,
                    100,
                );
            }

            $entry = AccountingEntry::create([
                'fiscal_year_id' => $fiscalYear->id,
                'entry_date' => $entryDate,
                'reference' => $reference,
                'source_type' => $sourceType,
                'source_id' => $sourceId,
                'is_locked' => false,
                'is_active' => true,
            ]);

            foreach ($lines as $line) {
                AccountingEntryLine::create([
                    'entry_id' => $entry->id,
                    'account_id' => $line['account_id'],
                    'cost_center_id' => $line['cost_center_id'] ?? null,
                    'debit' => $line['debit'] ?? 0,
                    'credit' => $line['credit'] ?? 0,
                ]);
            }

            return $entry;
        });
    }

    /**
     * Saisie manuelle à 2 lignes (Journal Comptable, ticket 10.4) — ajoute
     * la contrainte "compte débité ≠ compte crédité" (Document 01 §6.3)
     * PAR-DESSUS l'équilibre déjà vérifié par `record()`, jamais à sa place.
     */
    public function recordManual(
        string $debitAccountId,
        string $creditAccountId,
        float $amount,
        string $entryDate,
        ?string $reference = null,
        ?string $costCenterId = null,
    ): AccountingEntry {
        if ($debitAccountId === $creditAccountId) {
            throw new \InvalidArgumentException('Le compte débité doit être différent du compte crédité.');
        }

        return $this->record(
            lines: [
                ['account_id' => $debitAccountId, 'cost_center_id' => $costCenterId, 'debit' => $amount, 'credit' => 0],
                ['account_id' => $creditAccountId, 'cost_center_id' => $costCenterId, 'debit' => 0, 'credit' => $amount],
            ],
            entryDate: $entryDate,
            reference: $reference,
            sourceType: 'manual',
        );
    }

    /**
     * Modification d'une écriture manuelle existante (ticket 10.4) — MÊME
     * contrainte "compte débité ≠ compte crédité" que `recordManual()`,
     * jamais une seconde règle de validation qui pourrait diverger.
     * Remplace intégralement les 2 lignes existantes plutôt que de les
     * patcher en place — élimine tout risque de ligne orpheline si la
     * modification change le nombre ou l'ordre des comptes.
     */
    public function updateManual(
        AccountingEntry $entry,
        string $debitAccountId,
        string $creditAccountId,
        float $amount,
        string $entryDate,
        ?string $reference = null,
    ): AccountingEntry {
        if ($debitAccountId === $creditAccountId) {
            throw new \InvalidArgumentException('Le compte débité doit être différent du compte crédité.');
        }

        if ($entry->is_locked) {
            throw new \RuntimeException("Cette écriture est verrouillée (exercice clôturé) et ne peut plus être modifiée.");
        }

        DB::transaction(function () use ($entry, $debitAccountId, $creditAccountId, $amount, $entryDate, $reference) {
            $entry->lines()->delete();

            AccountingEntryLine::create(['entry_id' => $entry->id, 'account_id' => $debitAccountId, 'debit' => $amount, 'credit' => 0]);
            AccountingEntryLine::create(['entry_id' => $entry->id, 'account_id' => $creditAccountId, 'debit' => 0, 'credit' => $amount]);

            $entry->update(['entry_date' => $entryDate, 'reference' => $reference]);

            // Ticket 15.28 — LES LIGNES ONT ÉTÉ RECRÉÉES (nouveaux identifiants) : l'écriture a
            // changé, même si ni sa date ni sa référence n'ont bougé. Sans ce `touch()`, l'en-tête
            // n'est pas « sale », `updated_at` reste ancien et le tirage `since` du poste ne la
            // sert jamais : le poste garde les anciennes lignes, sans aucune erreur.
            $entry->touch();
        });

        return $entry->fresh('lines');
    }
}
