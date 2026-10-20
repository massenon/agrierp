<?php

namespace App\Livewire\Achats;

use App\Actions\SaisieDepenseAction;
use App\Exceptions\DepenseNonModifiableException;
use App\Models\Expense;
use App\Models\TreasuryAccount;
use App\Support\ExerciceChoisi;
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
 * "Reçu / Facture" : upload réel (`WithFileUploads`), même traitement que
 * `EnregistrerAchat` (ticket 5.2) et `contact-editeur.html` (ticket 1.6).
 */
#[Layout('layouts.app')]
class SaisieDepenses extends Component
{
    use \App\Livewire\Concerns\BornesCalendrierExercice;
    use WithPagination;

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
        // Ticket EX7 — le mois de référence de l'exercice affiché (le mois du jour, ou le dernier mois de 2026 lu en 2027).
        $mois = ExerciceChoisi::moisDeReference();
        $monthExpenses = Expense::where('is_active', true)
            ->whereMonth('expense_date', $mois->month)->whereYear('expense_date', $mois->year);

        return [
            'depenses_mois' => (float) (clone $monthExpenses)->sum('amount'),
        ];
    }

    /** Ticket EX7 (EF9) — les dépenses de l'exercice AFFICHÉ, PAGINÉES (25 par page) ; avant : toutes, sans fin. */
    public function getExpensesProperty()
    {
        [$debut, $fin] = ExerciceChoisi::bornes();

        return Expense::with('treasuryAccount')
            ->where('is_active', true)
            ->whereDate('expense_date', '>=', $debut)
            ->whereDate('expense_date', '<=', $fin)
            ->when($this->search, fn ($q) => $q->where('label', 'like', '%'.$this->search.'%'))
            ->when($this->statusFilter === 'Payée', fn ($q) => $q->where('status', 'payee'))
            ->when($this->statusFilter === 'En attente', fn ($q) => $q->where('status', 'en_attente'))
            ->orderByDesc('expense_date')
            // 🔴→✅ Ticket U14 — deux dépenses du même jour n'avaient pas d'ordre défini (MySQL rend l'ordre qu'il
            // veut) : l'identifiant les départage, ici et au poste (`DepensesRepository::depenses`).
            ->orderBy('id')
            ->paginate(ExerciceChoisi::PAR_PAGE, pageName: 'pageDepenses');
    }

    /** Un filtre change : retour à la première page. */
    public function updating(string $propriete): void
    {
        if (in_array($propriete, ['search', 'statusFilter'], true)) {
            $this->resetPage('pageDepenses');
        }
    }

    /**
     * Ticket EX7 (réponse à EX-Q5, décision D-U14-1) — la dépense en cours de modification est comptabilisée : son
     * champ « Date » est GRISÉ, motif en info-bulle (`SaisieDepenseAction::MOTIF_DATE_VERROUILLEE`). Confort : le refus
     * de `SaisieDepenseAction::modifier()` reste la garantie (sous « Montant »).
     */
    public function getDateVerrouilleeProperty(): bool
    {
        return $this->editingExpenseId !== null
            && Expense::whereKey($this->editingExpenseId)->whereNotNull('accounting_entry_id')->exists();
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

        $donnees = [
            'expense_date' => $this->expenseDate,
            'label' => $this->label,
            'category' => $this->category,
            'amount' => $this->amount,
            'treasury_account_id' => $this->treasuryAccountId,
        ];

        // 🔴→✅ TICKET U14 — création, modification et archivage passent par `SaisieDepenseAction`, le point de passage
        // que l'envoi des postes emprunte aussi (mêmes règles, mêmes effets, mêmes messages). Le justificatif n'est
        // stocké qu'une fois la modification admise (il l'était avant le refus d'une dépense comptabilisée).
        if ($this->editingExpenseId) {
            try {
                app(SaisieDepenseAction::class)->modifier(
                    $this->editingExpenseId,
                    $donnees,
                    $this->receiptFile ? $this->receiptFile->store('depenses-recus', 'local') : null,
                );
            } catch (DepenseNonModifiableException $e) {
                // ⚠️ UNE DÉPENSE DÉJÀ COMPTABILISÉE NE SE RÉÉCRIT PAS (14.33), une dépense archivée non plus (U14).
                $this->addError('amount', $e->getMessage());

                return;
            } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
                // 🔴→✅ Ticket EX5 (EF6, R4) — exercice clos ou absent : le motif sous « Date », jamais une erreur 500.
                $this->addError('expenseDate', $e->getMessage());

                return;
            }
        } else {
            try {
                [, $ecritureManquante] = app(SaisieDepenseAction::class)->creer(
                    $donnees,
                    null,
                    $this->receiptFile ? $this->receiptFile->store('depenses-recus', 'local') : null,
                );
            } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
                // 🔴→✅ Ticket EX5 (EF6, R4) — l'erreur 500 constatée le 20/10/2026 : le motif sous « Date ».
                $this->addError('expenseDate', $e->getMessage());

                return;
            }

            if ($ecritureManquante) {
                // Jamais silencieux — même discipline que le POS (14.23), les achats (14.24) et les avoirs (14.27).
                $this->dispatch('toast', message: "Dépense enregistrée — ATTENTION : écriture comptable non générée (compte de charge ou de trésorerie absent du plan comptable). À régulariser au Journal Comptable.", type: 'warning');
                $this->reset(['editingExpenseId', 'label', 'category', 'amount', 'receiptFile']);
                $this->expenseDate = now()->format('Y-m-d');

                return;
            }
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

        // 🔴→✅ TICKET 14.33 — CONTRE-PASSATION (écriture d'annulation de sens inverse, jamais suppression de
        // l'originale) et trésorerie réintégrée : `SaisieDepenseAction::archiver()` (U14, partagé avec les postes).
        try {
            $resultat = app(SaisieDepenseAction::class)->archiver($id);
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
            : 'Dépense archivée — trésorerie réintégrée et charge annulée.';

        $this->dispatch('toast', message: $message, type: 'warning');
    }

    public function render()
    {
        return view('livewire.achats.saisie-depenses', ['title' => 'Achats > Saisie des Dépenses']);
    }
}
