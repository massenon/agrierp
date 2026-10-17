<?php

namespace App\Livewire\Achats;

use App\Actions\RecordExpenseAccountingEntryAction;
use App\Models\AuditLog;
use App\Models\Expense;
use App\Models\TreasuryAccount;
use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;
use Livewire\WithFileUploads;

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
 * "Reçu / Facture" : upload réel (`WithFileUploads`), même traitement que
 * `EnregistrerAchat` (ticket 5.2) et `contact-editeur.html` (ticket 1.6).
 */
#[Layout('layouts.app')]
class SaisieDepenses extends Component
{
    use WithFileUploads;

    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    public ?string $editingExpenseId = null;

    public string $expenseDate = '';

    public string $label = '';

    public string $category = '';

    public ?float $amount = null;

    public string $treasuryAccountId = '';

    public $receiptFile = null;

    /** Ticket 14.33 — signale une dépense enregistrée sans écriture comptable. */
    private bool $ecritureManquante = false;

    /** Ticket 14.33 — modification refusée sur une dépense déjà comptabilisée. */
    private bool $conflitEcriture = false;

    public function mount(): void
    {
        $this->expenseDate = now()->format('Y-m-d');
    }

    public function getTreasuryAccountsProperty()
    {
        return TreasuryAccount::where('is_active', true)->orderBy('label')->get();
    }

    public function getKpisProperty(): array
    {
        $monthExpenses = Expense::where('is_active', true)
            ->whereMonth('expense_date', now()->month)->whereYear('expense_date', now()->year);

        return [
            'depenses_mois' => (float) (clone $monthExpenses)->sum('amount'),
        ];
    }

    public function getExpensesProperty()
    {
        return Expense::with('treasuryAccount')
            ->where('is_active', true)
            ->when($this->search, fn ($q) => $q->where('label', 'like', '%'.$this->search.'%'))
            ->when($this->statusFilter === 'Payée', fn ($q) => $q->where('status', 'payee'))
            ->when($this->statusFilter === 'En attente', fn ($q) => $q->where('status', 'en_attente'))
            ->orderByDesc('expense_date')
            ->get();
    }

    public function submitExpense(): void
    {
        // ⚠️⚠️ TICKET 14.62 — AUTORISATION AJOUTEE. Cette methode DECAISSE :
        // elle diminue le solde de tresorerie et passe une ecriture SYSCOHADA.
        // Elle n'etait protegee que par le middleware `can:view-achats` de la
        // route — un droit de LECTURE suffisait donc a depenser. La regle du
        // projet est explicite : autorisation de route ET `authorize()` en
        // premiere ligne de toute methode mutante.
        $this->authorize('manage-achats');

        $this->validate([
            'expenseDate' => ['required', 'date'],
            'label' => ['required', 'string', 'max:255'],
            'category' => ['required', 'string'],
            'amount' => ['required', 'numeric', 'min:1'],
            'treasuryAccountId' => ['required', 'exists:treasury_accounts,id'],
            'receiptFile' => ['nullable', 'image', 'max:5120'],
        ]);

        DB::transaction(function () {
            $receiptPath = $this->receiptFile ? $this->receiptFile->store('depenses-recus', 'local') : null;

            if ($this->editingExpenseId) {
                $expense = Expense::findOrFail($this->editingExpenseId);

                // ⚠️ UNE DÉPENSE DÉJÀ COMPTABILISÉE NE SE RÉÉCRIT PAS. Modifier
                // son montant ou son compte de charge ferait diverger le
                // registre des dépenses du grand livre, sans qu'aucun écran ne
                // le signale. La correction passe par une écriture au Journal
                // Comptable — même discipline que pour une immobilisation déjà
                // capitalisée (ticket 14.26).
                $montantChange = round((float) $this->amount, 2) !== round((float) $expense->amount, 2);

                if ($expense->accounting_entry_id && ($montantChange || $this->category !== $expense->category)) {
                    $this->conflitEcriture = true;

                    return;
                }

                // Réajuste la trésorerie : annule l'ancien montant, applique le nouveau.
                TreasuryAccount::where('id', $expense->treasury_account_id)->increment('balance', $expense->amount);
                $expense->update([
                    'expense_date' => $this->expenseDate,
                    'label' => $this->label,
                    'category' => $this->category,
                    'amount' => $this->amount,
                    'treasury_account_id' => $this->treasuryAccountId,
                    'receipt_path' => $receiptPath ?: $expense->receipt_path,
                ]);
                AuditLog::record('expense.updated', 'achats');
            } else {
                $expense = Expense::create([
                    'expense_date' => $this->expenseDate,
                    'label' => $this->label,
                    'category' => $this->category,
                    'amount' => $this->amount,
                    'treasury_account_id' => $this->treasuryAccountId,
                    'receipt_path' => $receiptPath,
                    'status' => 'payee',
                    'is_active' => true,
                ]);
                AuditLog::record('expense.created', 'achats');

                // 🔴→✅ TICKET 14.33 — ÉCRITURE COMPTABLE ENFIN GÉNÉRÉE.
                //
                // Le CDC §1.4 [M2] l'exige mot pour mot : « `RegisterExpense` →
                // Débit Classe 6 / Crédit Classe 5 ». Avant ce ticket, la
                // dépense décrémentait la trésorerie sans rien porter en
                // charge : carburant, électricité et transport n'apparaissaient
                // nulle part au Compte de Résultat, et le résultat net était
                // surestimé du total des dépenses de la période.
                $ecriture = app(RecordExpenseAccountingEntryAction::class)->execute($expense);

                if ($ecriture === null) {
                    // Jamais silencieux — même discipline que le POS (14.23),
                    // les achats (14.24) et les avoirs (14.27).
                    AuditLog::record('expense.accounting_entry_missing', 'comptabilite');
                    $this->ecritureManquante = true;
                }
            }

            TreasuryAccount::where('id', $this->treasuryAccountId)->decrement('balance', $this->amount);
        });

        if ($this->conflitEcriture) {
            $this->conflitEcriture = false;
            $this->addError('amount', "Cette dépense est déjà comptabilisée : son montant et son compte de charge ne peuvent plus être modifiés ici. Passez une écriture de correction au Journal Comptable.");

            return;
        }

        if ($this->ecritureManquante) {
            $this->ecritureManquante = false;
            $this->dispatch('toast', message: "Dépense enregistrée — ATTENTION : écriture comptable non générée (compte de charge ou de trésorerie absent du plan comptable). À régulariser au Journal Comptable.", type: 'warning');
            $this->reset(['editingExpenseId', 'label', 'category', 'amount', 'receiptFile']);
            $this->expenseDate = now()->format('Y-m-d');

            return;
        }

        $this->dispatch('toast', message: 'Dépense enregistrée avec succès.', type: 'success');
        $this->reset(['editingExpenseId', 'label', 'category', 'amount', 'receiptFile']);
        $this->expenseDate = now()->format('Y-m-d');
    }

    public function editExpense(string $id): void
    {
        $this->authorize('manage-achats');

        $expense = Expense::findOrFail($id);
        $this->editingExpenseId = $expense->id;
        $this->expenseDate = $expense->expense_date->format('Y-m-d');
        $this->label = $expense->label;
        $this->category = $expense->category;
        $this->amount = (float) $expense->amount;
        $this->treasuryAccountId = $expense->treasury_account_id;
    }

    public function archiveExpense(string $id): void
    {
        // Archiver une depense la retire des etats : meme niveau d'exigence.
        $this->authorize('manage-achats');

        $expense = Expense::findOrFail($id);

        // 🔴→✅ TICKET 14.33 — CONTRE-PASSATION. La trésorerie était réintégrée
        // sans que la charge le soit : le Compte de Résultat gardait une
        // dépense dont l'argent était revenu. Écriture d'annulation de sens
        // inverse, jamais suppression de l'originale — le grand livre est
        // immuable.
        $annulation = app(RecordExpenseAccountingEntryAction::class)->reverse($expense);

        TreasuryAccount::where('id', $expense->treasury_account_id)->increment('balance', $expense->amount);
        $expense->update(['is_active' => false]);
        AuditLog::record('expense.archived', 'achats');

        $message = $expense->accounting_entry_id && ! $annulation
            ? 'Dépense archivée — ATTENTION : écriture d\'annulation non générée. À régulariser au Journal Comptable.'
            : 'Dépense archivée — trésorerie réintégrée et charge annulée.';

        $this->dispatch('toast', message: $message, type: 'warning');
    }

    public function render()
    {
        return view('livewire.achats.saisie-depenses', ['title' => 'Achats > Saisie des Dépenses']);
    }
}
