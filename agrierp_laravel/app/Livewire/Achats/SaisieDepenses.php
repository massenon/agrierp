<?php

namespace App\Livewire\Achats;

use App\Actions\SaisieDepenseAction;
use App\Exceptions\DepenseNonModifiableException;
use App\Exceptions\DepenseNonComptabilisableException;
use App\Models\ChartOfAccount;
use App\Models\CostCenter;
use App\Models\Expense;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use App\Support\ExerciceChoisi;
use Illuminate\Validation\ValidationException;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;
use Livewire\WithFileUploads;
use Livewire\WithPagination;

/**
 * Ticket 5.8 (Sprint 5) — saisie-depenses.html → Livewire\Achats\SaisieDepenses
 * DERNIER TICKET DU SPRINT 5.
 * "Enregistrement des charges d'exploitation courantes de la ferme
 * (SYSCOHADA Classe 6)."
 *
 * Table `expenses` ajoutée, absente du schéma documenté — voir docblock
 * de la migration.
 *
 * ⚠️ KPI "Charges Fixes"/"Charges Variables" LAISSÉS EN ATTENTE,
 * SIGNALÉ EXPLICITEMENT : le formulaire source ne capture aucune
 * distinction Fixe/Variable par dépense — seuls Date/Libellé/Catégorie/
 * Montant/Compte sont demandés. Sans champ ni règle de classification
 * fiable dans le prototype, ces deux KPI ne peuvent pas être calculés
 * sans deviner une règle arbitraire (Document 00 §2.1 : pas de calcul
 * partiel deviné à partir de données incomplètes). "Dépenses du mois"
 * (total) reste réel.
 *
 * "Compte de Trésorerie Débité" étant obligatoire dans le formulaire, une
 * dépense saisie ici est immédiatement décaissée — `treasury_accounts.balance`
 * décrémenté réellement à l'enregistrement, statut toujours `payee`
 * (le statut `en_attente` visible sur une ligne de démonstration du
 * prototype ne correspond à aucun mécanisme de saisie réel ici — jamais
 * atteignable via ce formulaire, qui exige toujours un compte débité).
 *
 * 🔴→✅ TICKET DEP2 (PRD `docs/prd/depenses-multilignes.md`) — UNE DÉPENSE, PLUSIEURS LIGNES. La saisie passe dans une
 * MODALE « Nouvelle Dépense » à lignes dynamiques (libellé, compte de charge, montant ; total en direct) ; le tableau
 * affiche date, libellé-résumé, total, mode, pièce, et se déplie sur les lignes. Une dépense comptabilisée n'est PLUS
 * modifiable : on l'archive (contre-passation). Tout passe par `SaisieDepenseAction`.
 *
 * "Reçu / Facture" : upload réel (`WithFileUploads`), même traitement que
 * `EnregistrerAchat` (ticket 5.2) et `contact-editeur.html` (ticket 1.6).
 */
#[Layout('layouts.app')]
class SaisieDepenses extends Component
{
    use \App\Livewire\Concerns\BornesCalendrierExercice;
    use WithPagination;

    use WithFileUploads;

    public const MODALE = 'modal-depense';

    #[Url]
    public string $search = '';

    /** Filtre « Pièce » : '' (toutes), « Comptabilisée » ou « Sans pièce ». */
    #[Url]
    public string $pieceFilter = '';

    public ?string $editingExpenseId = null;

    public string $expenseDate = '';

    public string $paymentMode = '';

    public string $treasuryAccountId = '';

    public string $costCenterId = '';

    public string $supplierId = '';

    /** Ticket DEP7 (DEP-Q3) — « Règlement » (proposé quand un fournisseur est choisi) : `comptant` ou `credit` (`Expense::REGLEMENTS`). */
    public string $reglement = 'comptant';

    public string $beneficiary = '';

    public $receiptFile = null;

    /**
     * Les lignes de la modale : `id` (celui d'une ligne existante, pour qu'une modification la reconnaisse), `label`,
     * `chargeAccountId`, `amount` (texte saisi : un entier de francs).
     *
     * @var array<int, array{id: ?string, label: string, chargeAccountId: string, amount: string}>
     */
    public array $lines = [];

    public function mount(): void
    {
        $this->reinitialiserLeFormulaire();
    }

    private function reinitialiserLeFormulaire(): void
    {
        $this->reset(['editingExpenseId', 'paymentMode', 'treasuryAccountId', 'costCenterId', 'supplierId', 'reglement', 'beneficiary', 'receiptFile']);
        $this->resetErrorBag();
        $this->expenseDate = now()->format('Y-m-d');
        $this->lines = [self::ligneVide()];
    }

    /** @return array{id: ?string, label: string, chargeAccountId: string, amount: string} */
    private static function ligneVide(): array
    {
        return ['id' => null, 'label' => '', 'chargeAccountId' => '', 'amount' => ''];
    }

    public function getTreasuryAccountsProperty()
    {
        return TreasuryAccount::where('is_active', true)
            ->when($this->paymentMode !== '', fn ($q) => $q->where('type', $this->paymentMode))
            ->orderBy('label')->get();
    }

    /** Les comptes de CHARGE du plan comptable (classe 6) : la liste de chaque ligne. */
    public function getChargeAccountsProperty()
    {
        return ChartOfAccount::where('class', 6)->where('is_active', true)->orderBy('code')->get(['id', 'code', 'label']);
    }

    public function getCostCentersProperty()
    {
        return CostCenter::where('is_active', true)->orderBy('label')->get(['id', 'label']);
    }

    public function getSuppliersProperty()
    {
        return Supplier::where('is_active', true)->orderBy('name')->get(['id', 'name']);
    }

    /** Le total de la modale : la SOMME des lignes (jamais saisi), en francs entiers ; une ligne illisible compte 0. */
    public function getTotalProperty(): int
    {
        return (int) array_sum(array_map(
            fn ($l) => is_numeric($l['amount'] ?? null) ? (int) round((float) $l['amount']) : 0,
            $this->lines,
        ));
    }

    public function getKpisProperty(): array
    {
        // Ticket EX7 — le mois de référence de l'exercice affiché (le mois du jour, ou le dernier mois de 2026 lu en 2027).
        $mois = ExerciceChoisi::moisDeReference();
        $monthExpenses = Expense::where('is_active', true)
            ->whereMonth('expense_date', $mois->month)->whereYear('expense_date', $mois->year);

        return [
            'depenses_mois' => (float) (clone $monthExpenses)->sum('amount'),
        ];
    }

    /** Ticket EX7 (EF9) — les dépenses de l'exercice AFFICHÉ, PAGINÉES (25 par page) ; ticket DEP2 : avec leurs lignes. */
    public function getExpensesProperty()
    {
        [$debut, $fin] = ExerciceChoisi::bornes();

        return Expense::with(['lines.chargeAccount', 'treasuryAccount', 'accountingEntry', 'costCenter', 'supplier', 'creator'])
            ->where('is_active', true)
            ->whereDate('expense_date', '>=', $debut)
            ->whereDate('expense_date', '<=', $fin)
            ->when($this->search, fn ($q) => $q->where(fn ($w) => $w
                ->where('label', 'like', '%'.$this->search.'%')
                ->orWhereHas('lines', fn ($l) => $l->where('label', 'like', '%'.$this->search.'%'))))
            ->when($this->pieceFilter === 'Comptabilisée', fn ($q) => $q->whereNotNull('accounting_entry_id'))
            ->when($this->pieceFilter === 'Sans pièce', fn ($q) => $q->whereNull('accounting_entry_id'))
            ->orderByDesc('expense_date')
            // 🔴→✅ Ticket U14 — deux dépenses du même jour n'avaient pas d'ordre défini (MySQL rend l'ordre qu'il
            // veut) : l'identifiant les départage, ici et au poste (`DepensesRepository::depenses`).
            ->orderBy('id')
            ->paginate(ExerciceChoisi::PAR_PAGE, pageName: 'pageDepenses');
    }

    /** Un filtre change : retour à la première page. */
    public function updating(string $propriete): void
    {
        if (in_array($propriete, ['search', 'pieceFilter'], true)) {
            $this->resetPage('pageDepenses');
        }
    }

    /** Choisir le mode de paiement filtre les comptes de trésorerie ; un compte d'un autre type est abandonné. */
    public function updatedPaymentMode(): void
    {
        if ($this->treasuryAccountId !== '' && $this->paymentMode !== ''
            && TreasuryAccount::whereKey($this->treasuryAccountId)->value('type') !== $this->paymentMode) {
            $this->treasuryAccountId = '';
        }
    }

    /** Ticket DEP7 — sans fournisseur, pas de crédit : la dépense est payée comptant (trésorerie obligatoire, comme avant). */
    public function updatedSupplierId(): void
    {
        if ($this->supplierId === '') {
            $this->reglement = 'comptant';
        }
    }

    /** Ticket DEP7 — la dépense est-elle saisie À CRÉDIT (fournisseur choisi ET règlement « À crédit ») ? */
    public function getACreditProperty(): bool
    {
        return $this->supplierId !== '' && $this->reglement === 'credit';
    }

    /** Choisir un compte de trésorerie fixe le mode (son type) : les deux champs ne se contredisent jamais. */
    public function updatedTreasuryAccountId(): void
    {
        if ($this->treasuryAccountId !== '') {
            $this->paymentMode = (string) TreasuryAccount::whereKey($this->treasuryAccountId)->value('type');
        }
    }

    public function nouvelleDepense(): void
    {
        $this->authorize('manage-achats');

        $this->reinitialiserLeFormulaire();
        $this->dispatch('open-modal', name: self::MODALE);
    }

    public function addLine(): void
    {
        $this->lines[] = self::ligneVide();
    }

    /** Retire la ligne [$index] ; la dernière ligne ne se retire pas (le bouton est grisé). */
    public function removeLine(int $index): void
    {
        if (count($this->lines) > 1) {
            unset($this->lines[$index]);
            $this->lines = array_values($this->lines);
            $this->resetErrorBag();
        }
    }

    /** @return array<string, mixed> le document de `SaisieDepenseAction` */
    private function document(): array
    {
        return [
            'expense_date' => $this->expenseDate,
            // Ticket DEP7 — à crédit : aucune trésorerie ni mode (la dette crédite le 401, la caisse ne bouge pas).
            'treasury_account_id' => $this->aCredit ? null : $this->treasuryAccountId,
            'payment_mode' => $this->aCredit ? null : $this->paymentMode,
            'on_credit' => $this->aCredit,
            'cost_center_id' => $this->costCenterId !== '' ? $this->costCenterId : null,
            'supplier_id' => $this->supplierId !== '' ? $this->supplierId : null,
            'beneficiary' => $this->beneficiary,
            'lines' => array_map(fn ($l) => [
                'id' => $l['id'] ?? null,
                'label' => $l['label'] ?? '',
                'charge_account_id' => $l['chargeAccountId'] ?? '',
                'amount' => $l['amount'] ?? '',
            ], $this->lines),
        ];
    }

    /** Les erreurs de l'action (clés du document) sous les champs de la modale (clés du composant). */
    private function afficherLesErreurs(ValidationException $e): void
    {
        $carte = [
            'expense_date' => 'expenseDate', 'treasury_account_id' => 'treasuryAccountId', 'payment_mode' => 'paymentMode',
            'cost_center_id' => 'costCenterId', 'supplier_id' => 'supplierId', 'beneficiary' => 'beneficiary',
            'amount' => 'total', 'category' => 'formulaire', 'on_credit' => 'reglement',
        ];

        foreach ($e->errors() as $cle => $messages) {
            $cle = preg_replace('/^lines\.(\d+)\.charge_account_id$/', 'lines.$1.chargeAccountId', $cle);
            $cle = $carte[$cle] ?? $cle;
            foreach ($messages as $message) {
                $this->addError($cle, $message);
            }
        }
    }

    public function submitExpense(): void
    {
        // ⚠️⚠️ TICKET 14.62 — AUTORISATION AJOUTEE. Cette methode DECAISSE : elle diminue le solde de tresorerie et passe
        // une ecriture SYSCOHADA. Autorisation de route ET `authorize()` en premiere ligne de toute methode mutante.
        $this->authorize('manage-achats');

        $this->resetErrorBag();
        $this->validate(['receiptFile' => ['nullable', 'file', 'mimes:'.\App\Services\JustificatifService::FORMATS, 'max:'.\App\Services\JustificatifService::TAILLE_MAX_KO]]);

        $document = $this->document();
        $action = app(SaisieDepenseAction::class);

        // 🔴→✅ TICKET U14 — création et modification passent par `SaisieDepenseAction`, le point de passage que l'envoi
        // des postes emprunte aussi (mêmes règles, mêmes effets, mêmes messages). Le justificatif n'est stocké qu'une
        // fois la saisie admise.
        try {
            $action->valider($document, $this->editingExpenseId);
            $justificatif = $this->receiptFile ? $this->receiptFile->store('depenses-recus', 'local') : null;

            if ($this->editingExpenseId) {
                $action->modifier($this->editingExpenseId, $document, $justificatif);
            } else {
                $action->creer($document, null, $justificatif);
            }
        } catch (ValidationException $e) {
            $this->afficherLesErreurs($e);
            // Choisir un compte de trésorerie fixe le mode : un mode vide dit qu'aucun compte n'est choisi.
            if (! $this->aCredit && $this->paymentMode === '') {
                $this->addError('paymentMode', 'Le champ mode de paiement est obligatoire.');
            }

            return;
        } catch (DepenseNonModifiableException $e) {
            // ⚠️ UNE DÉPENSE COMPTABILISÉE EST IMMUABLE (14.33, DEP1), une dépense archivée ne se modifie pas non plus (U14).
            $this->addError('formulaire', $e->getMessage());

            return;
        } catch (DepenseNonComptabilisableException $e) {
            // Ticket DEP1 — la pièce ne peut pas être passée : RIEN n'est enregistré, le motif est dit sous le compte.
            $this->addError('treasuryAccountId', $e->getMessage());

            return;
        } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
            // 🔴→✅ Ticket EX5 (EF6, R4) — exercice clos ou absent : le motif sous « Date », jamais une erreur 500.
            $this->addError('expenseDate', $e->getMessage());

            return;
        }

        $this->dispatch('toast', message: 'Dépense enregistrée avec succès.', type: 'success');
        $this->dispatch('close-modal', name: self::MODALE);
        $this->reinitialiserLeFormulaire();
    }

    public function editExpense(string $id): void
    {
        $this->authorize('manage-achats');

        $expense = Expense::with('lines')->findOrFail($id);

        // Ticket EX5 — une dépense d'un exercice CLOS ne se modifie plus : le motif R4 de sa date, avant tout autre.
        $refusExercice = app(\App\Services\AccountingEntryService::class)->refusExerciceClos($expense->expense_date->format('Y-m-d'));
        if ($refusExercice !== null) {
            $this->dispatch('toast', message: $refusExercice, type: 'error');

            return;
        }

        // Ticket DEP1 — une dépense comptabilisée est immuable : pas de modale, le motif et le chemin de correction.
        if ($expense->accounting_entry_id !== null) {
            $this->dispatch('toast', message: SaisieDepenseAction::MESSAGE_DEJA_COMPTABILISEE, type: 'error');

            return;
        }
        if (! $expense->is_active) {
            $this->dispatch('toast', message: SaisieDepenseAction::MESSAGE_ARCHIVEE, type: 'error');

            return;
        }

        $this->resetErrorBag();
        $this->editingExpenseId = $expense->id;
        $this->expenseDate = $expense->expense_date->format('Y-m-d');
        $this->paymentMode = (string) ($expense->payment_mode ?? '');
        $this->treasuryAccountId = $expense->treasury_account_id;
        $this->costCenterId = (string) ($expense->cost_center_id ?? '');
        $this->supplierId = (string) ($expense->supplier_id ?? '');
        $this->reglement = 'comptant';   // une dépense modifiable est une reprise SANS pièce : jamais à crédit (DEP7)
        $this->beneficiary = (string) ($expense->beneficiary ?? '');
        $this->receiptFile = null;
        $this->lines = $expense->lines->map(fn ($l) => [
            'id' => $l->id, 'label' => $l->label, 'chargeAccountId' => $l->charge_account_id,
            'amount' => (string) (int) round((float) $l->amount),
        ])->all() ?: [self::ligneVide()];

        $this->dispatch('open-modal', name: self::MODALE);
    }

    public function archiveExpense(string $id): void
    {
        // Archiver une depense la retire des etats : meme niveau d'exigence.
        $this->authorize('manage-achats');

        // Ticket DEP7 — une dépense À CRÉDIT s'archive en annulant sa dette (aucune trésorerie n'avait bougé) : le toast le dit.
        $aCredit = (bool) Expense::whereKey($id)->value('on_credit');

        // 🔴→✅ TICKET 14.33 — CONTRE-PASSATION (écriture d'annulation de sens inverse, jamais suppression de
        // l'originale) et trésorerie réintégrée : `SaisieDepenseAction::archiver()` (U14, partagé avec les postes).
        try {
            $resultat = app(SaisieDepenseAction::class)->archiver($id);
        } catch (DepenseNonModifiableException $e) {
            // Ticket DEP7 — dépense à crédit déjà réglée en tout ou partie : rien n'est archivé, le motif est dit.
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
            // 🔴→✅ Ticket EX5 — dépense d'un exercice clos, ou contre-passation du jour sans exercice : motif R4.
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        // 🔴→✅ U14 — déjà archivée (double clic, page restée ouverte) : rien n'est refait, rien à annoncer.
        if ($resultat === SaisieDepenseAction::DEJA_ARCHIVEE) {
            return;
        }

        $message = $resultat === SaisieDepenseAction::ARCHIVEE_SANS_ANNULATION
            ? 'Dépense archivée — ATTENTION : écriture d\'annulation non générée. À régulariser au Journal Comptable.'
            : ($aCredit ? 'Dépense archivée — dette fournisseur annulée et charge annulée.' : 'Dépense archivée — trésorerie réintégrée et charge annulée.');

        $this->dispatch('toast', message: $message, type: 'warning');
    }

    public function render()
    {
        return view('livewire.achats.saisie-depenses', ['title' => 'Achats > Saisie des Dépenses']);
    }
}
