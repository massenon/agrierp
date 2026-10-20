<?php

namespace App\Actions;

use App\Exceptions\DepenseNonModifiableException;
use App\Models\AuditLog;
use App\Models\Expense;
use App\Models\TreasuryAccount;
use App\Services\AccountingEntryService;
use Illuminate\Support\Facades\DB;

/**
 * Ticket U14 — POINT DE PASSAGE UNIQUE d'une dépense : création, modification, archivage.
 *
 * Ces trois gestes vivaient dans `Livewire\Achats\SaisieDepenses` (web) et, pour la seule création, recopiés dans
 * `SyncController::pushExpenses` (poste) — sans le journal d'audit ni l'avertissement « écriture non générée ». Le
 * poste modifie et archive désormais ses dépenses comme le web : les deux chemins passent ici, avec les mêmes règles,
 * les mêmes effets (trésorerie, écriture, contre-passation, audit) et les mêmes messages.
 *
 * Règles (celles de `SaisieDepenses` depuis 14.33, plus les trois correctifs U14 marqués 🔴→✅) :
 *  - création : `payee`, décaissée tout de suite (trésorerie − montant), écriture Débit 6 / Crédit 5 ; écriture non
 *    générée (plan comptable incomplet) → `expense.accounting_entry_missing`, jamais silencieux ;
 *  - modification : trésorerie réajustée (ancien compte + ancien montant, nouveau compte − nouveau montant) ; une
 *    dépense COMPTABILISÉE ne change ni de date (D-U14-1, EX5), ni de montant, ni de compte de charge, ni de compte
 *    de trésorerie ([MESSAGE_DEJA_COMPTABILISEE]) ;
 *  - EX5 : exercice clos (date d'origine ou nouvelle) ou absent → motif R4, avant toute écriture ;
 *  - archivage : contre-passation datée du jour, trésorerie réintégrée, `is_active = false`.
 *
 * ⚠️ VERROUS : la dépense est relue SOUS VERROU (`lockForUpdate`) avant toute écriture, puis la trésorerie est touchée
 * — même ordre partout. Deux gestes simultanés sur la même dépense (deux onglets, le web et un poste) passent l'un
 * après l'autre, et le second voit l'état laissé par le premier.
 */
class SaisieDepenseAction
{
    /**
     * 🔴→✅ Ticket U14 — le COMPTE DE TRÉSORERIE rejoint le montant et le compte de charge. Le changer sur une dépense
     * déjà comptabilisée déplaçait l'argent dans `treasury_accounts` (ancien compte +, nouveau −) sans toucher
     * l'écriture, qui créditait toujours l'ancien compte de classe 5 : les deux livres de trésorerie divergeaient pour
     * les DEUX comptes, et l'archivage contre-passait ensuite sur le nouveau.
     */
    public const MESSAGE_DEJA_COMPTABILISEE = 'Cette dépense est déjà comptabilisée : sa date, son montant, son compte de charge et son compte de trésorerie ne peuvent plus être modifiés ici. Passez une écriture de correction au Journal Comptable.';

    /**
     * 🔴→✅ Ticket U14 — modifier une dépense ARCHIVÉE (page restée ouverte au web, ou poste qui ne l'a pas encore appris)
     * réajustait la trésorerie d'une dépense déjà réintégrée : la caisse perdait le montant une seconde fois.
     */
    /**
     * Ticket EX7 (réponse à EX-Q5) — info-bulle du champ « Date » GRISÉ d'une dépense comptabilisée, au web
     * (`SaisieDepenses`) puis au poste (`SaisieDepensesScreen`), mot pour mot. Le refus à l'enregistrement
     * ([MESSAGE_DEJA_COMPTABILISEE], sous « Montant ») reste la garantie (D-U14-1).
     */
    public const MOTIF_DATE_VERROUILLEE = 'Dépense déjà comptabilisée : sa date ne peut plus être modifiée.';

    public const MESSAGE_ARCHIVEE = 'Cette dépense est archivée : elle ne peut plus être modifiée.';

    public const ARCHIVEE = 'archivee';

    public const ARCHIVEE_SANS_ANNULATION = 'archivee_sans_annulation';

    public const DEJA_ARCHIVEE = 'deja_archivee';

    /**
     * @param  array{expense_date: string, label: string, category: string, amount: float|int|string, treasury_account_id: string}  $donnees
     * @return array{0: Expense, 1: bool}  la dépense, et VRAI si son écriture n'a pas pu être générée
     */
    public function creer(array $donnees, ?string $id = null, ?string $justificatif = null): array
    {
        // 🔴→✅ Ticket EX5 (EF5, EF6, R4) — un exercice CLOS est jugé AVANT tout effet (motif R4 sous « Date » au web, refus
        // motivé à l'envoi du poste) : une dépense sans écriture possible (compte de charge absent) y passait. Un exercice
        // ABSENT est jugé par l'écriture (`record()`, filet R2 compris), dans la transaction : rien n'est écrit.
        app(AccountingEntryService::class)->refuserSiExerciceClos($donnees['expense_date']);

        return DB::transaction(function () use ($donnees, $id, $justificatif) {
            $depense = new Expense();
            if ($id !== null) {
                // ⚠️ `id` n'est pas remplissable : `create(['id' => …])` l'ignorerait en silence (piège 14.78).
                $depense->id = $id;
            }
            $depense->fill([
                'expense_date' => $donnees['expense_date'],
                'label' => $donnees['label'],
                'category' => $donnees['category'],
                'amount' => $donnees['amount'],
                'treasury_account_id' => $donnees['treasury_account_id'],
                'receipt_path' => $justificatif,
                // Une dépense saisie est immédiatement décaissée : le compte débité est obligatoire.
                'status' => 'payee',
                'is_active' => true,
            ]);
            $depense->save();
            AuditLog::record('expense.created', 'achats');

            // TICKET 14.33 — Débit Classe 6 / Crédit Classe 5 (CDC §1.4 [M2]).
            $ecriture = app(RecordExpenseAccountingEntryAction::class)->execute($depense);
            if ($ecriture === null) {
                AuditLog::record('expense.accounting_entry_missing', 'comptabilite');
            }

            TreasuryAccount::where('id', $donnees['treasury_account_id'])->decrement('balance', $donnees['amount']);

            return [$depense->fresh(), $ecriture === null];
        });
    }

    /**
     * @param  array{expense_date: string, label: string, category: string, amount: float|int|string, treasury_account_id: string}  $donnees
     *
     * @throws DepenseNonModifiableException
     */
    public function modifier(string $id, array $donnees, ?string $justificatif = null): Expense
    {
        return DB::transaction(function () use ($id, $donnees, $justificatif) {
            $depense = Expense::query()->whereKey($id)->lockForUpdate()->firstOrFail();

            if (! $depense->is_active) {
                throw new DepenseNonModifiableException(self::MESSAGE_ARCHIVEE);
            }

            // 🔴→✅ Ticket EX5 (EF5) — une dépense d'un exercice CLOS ne se modifie plus (motif R4 de sa date), et ne passe
            // pas non plus dans un exercice clos.
            $ancienneDate = $depense->expense_date->format('Y-m-d');
            $nouvelleDate = \Illuminate\Support\Carbon::parse($donnees['expense_date'])->format('Y-m-d');
            app(AccountingEntryService::class)->refuserSiExerciceClos($ancienneDate);
            app(AccountingEntryService::class)->refuserSiExerciceClos($nouvelleDate);

            // ⚠️ UNE DÉPENSE DÉJÀ COMPTABILISÉE NE SE RÉÉCRIT PAS (14.33) : la correction passe par une écriture au
            // Journal Comptable — même discipline que pour une immobilisation déjà capitalisée (14.26).
            // 🔴→✅ Décision D-U14-1 du 20/10/2026 — SA DATE NON PLUS : changée seule, elle faisait passer la dépense dans
            // un autre jour (ou un autre exercice) pendant que son écriture restait à l'ancienne date.
            $montantChange = round((float) $donnees['amount'], 2) !== round((float) $depense->amount, 2);
            if ($depense->accounting_entry_id && ($montantChange
                || $nouvelleDate !== $ancienneDate
                || $donnees['category'] !== $depense->category
                || $donnees['treasury_account_id'] !== $depense->treasury_account_id)) {
                throw new DepenseNonModifiableException(self::MESSAGE_DEJA_COMPTABILISEE);
            }

            // Réajuste la trésorerie : annule l'ancien montant, applique le nouveau.
            TreasuryAccount::where('id', $depense->treasury_account_id)->increment('balance', $depense->amount);
            $depense->update([
                'expense_date' => $donnees['expense_date'],
                'label' => $donnees['label'],
                'category' => $donnees['category'],
                'amount' => $donnees['amount'],
                'treasury_account_id' => $donnees['treasury_account_id'],
                'receipt_path' => $justificatif ?: $depense->receipt_path,
            ]);
            AuditLog::record('expense.updated', 'achats');
            TreasuryAccount::where('id', $donnees['treasury_account_id'])->decrement('balance', $donnees['amount']);

            return $depense->fresh();
        });
    }

    /**
     * @return string  [ARCHIVEE], [ARCHIVEE_SANS_ANNULATION] (écriture d'annulation non générée : à dire) ou
     *                 [DEJA_ARCHIVEE] (rien n'est refait : un second archivage ne réintègre pas une seconde fois)
     */
    public function archiver(string $id): string
    {
        return DB::transaction(function () use ($id) {
            $depense = Expense::query()->whereKey($id)->lockForUpdate()->firstOrFail();

            // 🔴→✅ Ticket U14 — un second archivage (double clic, page restée ouverte, renvoi d'un poste) réintégrait
            // une seconde fois le montant et contre-passait deux fois la charge.
            if (! $depense->is_active) {
                return self::DEJA_ARCHIVEE;
            }

            // 🔴→✅ Ticket EX5 (EF5) — une dépense d'un exercice CLOS ne s'archive plus : elle disparaîtrait des états de
            // cet exercice, et sa trésorerie serait réintégrée après coup. Motif R4 de sa date.
            app(AccountingEntryService::class)->refuserSiExerciceClos($depense->expense_date->format('Y-m-d'));

            // TICKET 14.33 — CONTRE-PASSATION, jamais suppression de l'originale : le grand livre est immuable.
            $annulation = app(RecordExpenseAccountingEntryAction::class)->reverse($depense);

            TreasuryAccount::where('id', $depense->treasury_account_id)->increment('balance', $depense->amount);
            $depense->update(['is_active' => false]);
            AuditLog::record('expense.archived', 'achats');

            return $depense->accounting_entry_id && ! $annulation ? self::ARCHIVEE_SANS_ANNULATION : self::ARCHIVEE;
        });
    }

    /**
     * Vrai si [$donnees] décrit exactement [$depense] (même jour, libellé, compte de charge, montant au centime, compte
     * de trésorerie) : un renvoi par un poste d'une saisie déjà reçue, à acquitter sans rien rejouer.
     *
     * @param  array{expense_date: string, label: string, category: string, amount: float|int|string, treasury_account_id: string}  $donnees
     */
    public function identique(Expense $depense, array $donnees): bool
    {
        return $depense->expense_date?->format('Y-m-d') === \Illuminate\Support\Carbon::parse($donnees['expense_date'])->format('Y-m-d')
            && $depense->label === $donnees['label']
            && $depense->category === $donnees['category']
            && round((float) $depense->amount, 2) === round((float) $donnees['amount'], 2)
            && $depense->treasury_account_id === $donnees['treasury_account_id'];
    }
}
