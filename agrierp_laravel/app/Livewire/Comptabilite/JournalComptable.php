<?php

namespace App\Livewire\Comptabilite;

use App\Models\AccountingEntry;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Services\AccountingEntryService;
use App\Support\ExerciceChoisi;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;
use Livewire\WithPagination;

/**
 * Ticket 10.4 (Sprint 10) — journal-comptable.html → Livewire\Comptabilite\JournalComptable
 * "Écritures comptables générées automatiquement (double entrée
 * SYSCOHADA)."
 *
 * ⚠️ VALIDATION BLOQUANTE SERVEUR RÉELLE : "compte débité ≠ compte
 * crédité" appliquée par `AccountingEntryService::recordManual()`/
 * `updateManual()` (ticket 10.2) — jamais un simple contrôle JS
 * côté client contournable. Toute tentative avec le même compte des
 * deux côtés est rejetée avant d'atteindre la base, message d'erreur
 * explicite affiché à l'écran (jamais une erreur 500 silencieuse).
 *
 * Numérotation `OD-{année}-{séquence}` (Opération Diverse, terminologie
 *
 * 🔴→✅ EXTENSION DU PATTERN RBAC CRUD AU NIVEAU ACTION (référence
 * initiale : `PlanComptable`) — `$this->authorize('manage-comptabilite')`
 * ajouté aux 4 méthodes mutantes, boutons masqués côté vue pour un rôle
 * n'ayant que `view-comptabilite` sans `manage-comptabilite`.
 * SYSCOHADA) portée par `reference` — le schéma documenté (§16) ne
 * prévoit qu'un seul champ texte libre `reference`, pas de colonne
 * "libellé" séparée : le numéro de pièce ET le libellé saisi y sont
 * combinés (`OD-2026-0001 — Achat aliment ponte`), jamais un champ
 * inventé hors schéma pour stocker le libellé séparément.
 *
 * Archivage (`is_active = false`) bloqué si l'écriture est verrouillée
 * (`is_locked`, posé par une future clôture d'exercice réelle au ticket
 * 10.6) — jamais un archivage silencieux d'une écriture qui ne devrait
 * plus bouger. Même contrôle sur "Modifier".
 *
 * ⚠️ Ce journal n'affichera QUE les écritures manuelles pour l'instant
 * (aucune autre source n'existe encore, rétro-câblage POS/Achats/Paie
 * explicitement différé au ticket 10.2) — mais interroge déjà
 * `accounting_entries` dans son ensemble, sans filtre sur `source_type` :
 * dès qu'un autre module générera des écritures réelles, elles
 * apparaîtront ici automatiquement, sans aucune modification de ce
 * composant.
 */
#[Layout('layouts.app')]
class JournalComptable extends Component
{
    use WithPagination;

    #[Url]
    public string $search = '';

    public ?string $editingId = null;

    public string $entryDate = '';

    public string $label = '';

    public string $debitAccountId = '';

    public string $creditAccountId = '';

    public ?float $amount = null;

    public function mount(): void
    {
        $this->entryDate = now()->format('Y-m-d');
    }

    public function getAccountsProperty()
    {
        return ChartOfAccount::where('is_active', true)->orderBy('code')->get();
    }

    public function getKpisProperty(): array
    {
        // Ticket EX7 — le mois de référence de l'exercice affiché (le mois du jour, ou le dernier mois de 2026 lu en 2027).
        $mois = ExerciceChoisi::moisDeReference();
        $monthEntries = AccountingEntry::with('lines')
            ->where('is_active', true)
            ->whereMonth('entry_date', $mois->month)->whereYear('entry_date', $mois->year)
            ->get();

        return [
            'ecritures_mois' => $monthEntries->count(),
            'total_debit' => $monthEntries->sum(fn ($e) => $e->total_debit),
            'total_credit' => $monthEntries->sum(fn ($e) => $e->total_credit),
        ];
    }

    /**
     * Ticket EX7 (EF9) — les écritures de l'exercice AFFICHÉ, PAGINÉES (25 par page), au lieu des 100 dernières toutes
     * années confondues : avec le volume, l'année N disparaissait de l'écran dès N+1.
     */
    private function requeteEcritures()
    {
        [$debut, $fin] = ExerciceChoisi::bornes();

        return AccountingEntry::with(['lines.account'])
            ->where('is_active', true)
            ->whereDate('entry_date', '>=', $debut)
            ->whereDate('entry_date', '<=', $fin)
            ->when($this->search, fn ($q) => $q->where('reference', 'like', '%'.$this->search.'%'))
            ->orderByDesc('entry_date')
            ->orderByDesc('created_at')
            ->orderByDesc('id');
    }

    public function getEntriesProperty()
    {
        return $this->requeteEcritures()->paginate(ExerciceChoisi::PAR_PAGE, pageName: 'pageJournal');
    }

    /** Toutes les écritures de l'exercice affiché (recherche comprise) : l'export PDF, jamais la seule page affichée. */
    public function ecrituresDeLExercice()
    {
        return $this->requeteEcritures()->get();
    }

    public function updatingSearch(): void
    {
        $this->resetPage('pageJournal');
    }

    public function debitLine(AccountingEntry $entry)
    {
        return $entry->lines->firstWhere('debit', '>', 0);
    }

    public function creditLine(AccountingEntry $entry)
    {
        return $entry->lines->firstWhere('credit', '>', 0);
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR VÉRIFICATION NIVEAU 2 : bouton "Exporter
     * PDF" totalement absent — réutilise `debitLine()`/`creditLine()`
     * déjà réels (un seul point de vérité), même schéma d'export établi
     * ailleurs dans ce projet.
     */
    public function exportJournalPdf()
    {
        $this->authorize('view-comptabilite');

        $entries = $this->ecrituresDeLExercice();

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.journal-comptable',
            ['entries' => $entries, 'component' => $this],
            'Journal Comptable',
            'Exercice '.ExerciceChoisi::annee().' — état au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'journal-comptable-'.now()->format('Y-m-d').'.pdf');
    }

    public function newEntry(): void
    {
        $this->authorize('manage-comptabilite');

        $this->reset(['editingId', 'label', 'debitAccountId', 'creditAccountId', 'amount']);
        $this->entryDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-create-journal-comptable');
    }

    public function editEntry(string $id): void
    {
        $this->authorize('manage-comptabilite');

        $entry = AccountingEntry::with('lines')->findOrFail($id);

        // Écriture verrouillée par la clôture ; ticket EX4 : à-nouveau ou sa contre-passation ; ticket EX5 : exercice
        // clos. Le refus vient du service, au même texte qu'à l'enregistrement — le formulaire ne s'ouvre pas.
        try {
            app(AccountingEntryService::class)->verifierModifiable($entry);
        } catch (\App\Exceptions\EcritureVerrouilleeException|\App\Exceptions\ClosedFiscalYearException $e) {
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        $this->editingId = $entry->id;
        $this->entryDate = $entry->entry_date->format('Y-m-d');
        $this->debitAccountId = $this->debitLine($entry)?->account_id ?? '';
        $this->creditAccountId = $this->creditLine($entry)?->account_id ?? '';
        $this->amount = (float) $entry->total_debit;
        $this->label = $entry->reference ? trim(explode('—', $entry->reference, 2)[1] ?? '') : '';
        $this->dispatch('open-modal', name: 'modal-create-journal-comptable');
    }

    public function saveEntry(): void
    {
        $this->authorize('manage-comptabilite');

        $this->validate([
            'entryDate' => ['required', 'date'],
            'label' => ['required', 'string', 'max:255'],
            'debitAccountId' => ['required', 'exists:chart_of_accounts,id'],
            'creditAccountId' => ['required', 'exists:chart_of_accounts,id'],
            'amount' => ['required', 'numeric', 'min:1'],
        ]);

        if ($this->debitAccountId === $this->creditAccountId) {
            $this->addError('creditAccountId', 'Le compte à créditer doit être différent du compte à débiter.');

            return;
        }

        // 🔴→✅ TICKET 14.14 — APPLICATION RÉELLE DE LA CLÔTURE PÉRIODIQUE.
        // C'est ce contrôle qui fait la différence entre une fonctionnalité et
        // une liste décorative : sans lui, clôturer un mois n'empêcherait
        // strictement rien. Vaut pour une création comme pour une
        // modification — antidater une écriture dans un mois clos est
        // exactement le contournement à interdire.
        if (\App\Models\PeriodicClosure::isDateLocked($this->entryDate)) {
            $this->addError('entryDate', 'Ce mois est clôturé — aucune écriture ne peut y être ajoutée ni modifiée. Un Administrateur peut le déclôturer exceptionnellement.');

            return;
        }

        try {
            $service = app(AccountingEntryService::class);

            if ($this->editingId) {
                $entry = AccountingEntry::findOrFail($this->editingId);
                $existingReference = explode('—', (string) $entry->reference, 2)[0];
                $reference = trim($existingReference).' — '.$this->label;
                $service->updateManual($entry, $this->debitAccountId, $this->creditAccountId, $this->amount, $this->entryDate, $reference);
                $message = 'Modification enregistrée avec succès.';
                AuditLog::record('accounting_entry.updated', 'comptabilite');
            } else {
                $reference = AccountingEntry::generateReference().' — '.$this->label;
                $service->recordManual($this->debitAccountId, $this->creditAccountId, $this->amount, $this->entryDate, $reference);
                $message = 'Écriture enregistrée avec succès.';
                AuditLog::record('accounting_entry.created', 'comptabilite');
            }

            $this->dispatch('close-modal', name: 'modal-create-journal-comptable');
            $this->dispatch('toast', message: $message, type: 'success');
        } catch (\Throwable $e) {
            // Ticket U5 : le motif d'une exception du framework (SQL…) n'est pas montré en anglais.
            $this->dispatch('toast', message: \App\Support\MessagesErreurFr::pourUtilisateur($e), type: 'error');
        }
    }

    public function archiveEntry(string $id): void
    {
        $this->authorize('manage-comptabilite');

        $entry = AccountingEntry::findOrFail($id);

        // Tickets EX4 / EX5 — mêmes refus que la modification (verrouillée, à-nouveau, exercice clos), dans le service.
        try {
            app(AccountingEntryService::class)->archiver($entry);
        } catch (\App\Exceptions\EcritureVerrouilleeException|\App\Exceptions\ClosedFiscalYearException $e) {
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        AuditLog::record('accounting_entry.archived', 'comptabilite');
        $this->dispatch('toast', message: 'Écriture archivée avec succès.', type: 'warning');
    }

    public function render()
    {
        return view('livewire.comptabilite.journal-comptable', ['title' => 'Comptabilité > Journal']);
    }
}
