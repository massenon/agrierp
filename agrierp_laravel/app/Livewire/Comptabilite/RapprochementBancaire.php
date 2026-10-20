<?php

namespace App\Livewire\Comptabilite;

use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Services\BankReconciliationService;
use App\Support\ExerciceChoisi;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;
use Livewire\WithFileUploads;

/**
 * Ticket 14.8 (Sprint 14) — rapprochement-bancaire.html → Livewire\Comptabilite\RapprochementBancaire
 * "Pointage entre le Grand Livre (compte 521 — Banques) et le relevé bancaire
 * importé."
 *
 * 5e et dernier écran comptable de la série — le module Comptabilité est
 * désormais réellement complet côté Laravel.
 *
 * ⚠️ CE N'ÉTAIT PAS UNE SIMPLE CONVERSION D'ÉCRAN : le prototype se contente
 * d'un `onchange` affichant un toast (« Traitement du relevé simulé pour
 * cette démonstration »), sans persister ni traiter quoi que ce soit. Un
 * rapprochement réel exige une table de lignes de relevé et un import
 * véritable — construits ici (`bank_statement_lines`,
 * `BankReconciliationService::importCsv()`). Reprendre le bouton sans
 * l'import aurait produit un écran décoratif, ce que la politique « zéro
 * placeholder » interdit explicitement.
 *
 * Le lettrage automatique et l'équation de rapprochement sont documentés dans
 * `BankReconciliationService` — notamment la règle « une ligne n'est appariée
 * qu'une seule fois », qui évite de masquer un doublon réel.
 *
 * ⚠️ Le sélecteur de compte n'est pas figé sur 521/5212 comme dans le
 * prototype : il liste les comptes de TRÉSORERIE réels (classe 5) du plan
 * comptable. Le prototype cite `521`/`5212` quand le seeder porte
 * `521101`/`521201` — écart déjà signalé au ticket 14.1, que cet écran évite
 * en n'écrivant aucun code de compte en dur.
 */
#[Layout('layouts.app')]
class RapprochementBancaire extends Component
{
    use WithFileUploads;

    #[Url]
    public string $accountId = '';

    #[Url]
    public string $startDate = '';

    #[Url]
    public string $endDate = '';

    public $releve;

    public function mount(): void
    {
        // Ticket EX7 (EF9) — période par défaut DANS l'exercice affiché (voir `GrandLivre::mount`).
        [$debut, $fin] = ExerciceChoisi::periodeParDefaut(now()->startOfMonth()->format('Y-m-d'), now()->format('Y-m-d'));
        [$this->startDate, $this->endDate] = ExerciceChoisi::bornerPeriode($this->startDate !== '' ? $this->startDate : $debut, $this->endDate !== '' ? $this->endDate : $fin);

        if ($this->accountId === '') {
            $this->accountId = (string) ($this->treasuryAccounts->first()?->id ?? '');
        }
    }

    /** Ticket EX7 (EF9) — une date saisie hors de l'exercice affiché est ramenée à sa borne. */
    public function updatedStartDate(): void
    {
        [$this->startDate, $this->endDate] = ExerciceChoisi::bornerPeriode($this->startDate, $this->endDate);
    }

    public function updatedEndDate(): void
    {
        $this->updatedStartDate();
    }

    /**
     * Comptes de trésorerie réels (classe 5) — jamais une liste codée en dur.
     *
     * TICKET 15.27 : le plan SYSCOHADA importé ajoute des dizaines de comptes de classe 5 (5, 50, 57, 5711…, regroupements
     * compris) qui ne sont pas des comptes bancaires de la ferme. La liste reste donc celle d'AVANT l'import : les comptes
     * de classe 5 rattachés à un compte de trésorerie (`treasury_accounts.account_code`), ou déjà mouvementés par une
     * écriture ou un relevé. Aucune règle d'« imputabilité » n'est inventée : c'est le cabinet FAGUEZ qui la fixera (phase B).
     */
    public function getTreasuryAccountsProperty()
    {
        $rattaches = \App\Models\TreasuryAccount::query()->whereNotNull('account_code')->pluck('account_code')->all();

        return ChartOfAccount::where('is_active', true)
            ->where('class', 5)
            ->where(fn ($q) => $q
                ->whereIn('code', $rattaches)
                ->orWhereIn('id', \App\Models\AccountingEntryLine::query()->select('account_id'))
                ->orWhereIn('id', \App\Models\BankStatementLine::query()->whereNotNull('account_id')->select('account_id')))
            ->orderBy('code')
            ->get();
    }

    public function getSelectedAccountProperty(): ?ChartOfAccount
    {
        return $this->accountId !== '' ? ChartOfAccount::find($this->accountId) : null;
    }

    public function getReconciliationProperty(): array
    {
        if ($this->accountId === '') {
            return [
                'ledger' => [], 'statement' => [], 'opening_balance' => 0.0,
                'solde_livre' => 0.0, 'solde_releve' => 0.0, 'en_instance' => 0.0,
                'nouveau_non_saisi' => 0.0, 'ecart' => 0.0, 'is_balanced' => true,
            ];
        }

        return app(BankReconciliationService::class)
            ->reconcile($this->accountId, $this->startDate, $this->endDate);
    }

    public function importReleve(): void
    {
        $this->authorize('manage-comptabilite');

        $this->validate([
            'releve' => ['required', 'file', 'max:2048'],
            'accountId' => ['required', 'exists:chart_of_accounts,id'],
        ], [], ['releve' => 'relevé']);

        $contenu = file_get_contents($this->releve->getRealPath());

        $resultat = app(BankReconciliationService::class)->importCsv($this->accountId, $contenu);

        AuditLog::record('bank_statement.imported', 'comptabilite');

        $this->reset('releve');
        // Le rapprochement doit repartir des lignes qui viennent d'être importées.
        unset($this->reconciliation);

        $message = $resultat['imported'].' ligne(s) importée(s).';

        if ($resultat['skipped'] > 0) {
            // Jamais silencieux : une ligne ignorée sans avertissement
            // produirait un écart de rapprochement inexplicable.
            $message .= ' '.$resultat['skipped'].' ligne(s) illisible(s) ignorée(s) — vérifiez le format date;libellé;montant.';
        }

        $this->dispatch('toast', message: $message, type: $resultat['skipped'] > 0 ? 'warning' : 'success');
    }

    public function exportRapprochementPdf()
    {
        $this->authorize('view-comptabilite');

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.rapprochement-bancaire',
            ['reconciliation' => $this->reconciliation, 'account' => $this->selectedAccount],
            'Rapprochement Bancaire'.($this->selectedAccount ? ' — Compte '.$this->selectedAccount->code : ''),
            'Période du '.\Carbon\Carbon::parse($this->startDate)->format('d/m/Y').' au '.\Carbon\Carbon::parse($this->endDate)->format('d/m/Y')
        );

        return response()->streamDownload(
            fn () => print ($pdf->output()),
            'rapprochement-bancaire-'.now()->format('Y-m-d').'.pdf'
        );
    }

    public function render()
    {
        return view('livewire.comptabilite.rapprochement-bancaire', ['title' => 'Comptabilité > Rapprochement Bancaire']);
    }
}
