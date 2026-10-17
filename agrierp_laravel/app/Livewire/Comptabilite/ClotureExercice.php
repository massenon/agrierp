<?php

namespace App\Livewire\Comptabilite;

use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\PeriodicClosure;
use App\Services\AccountingEntryService;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use App\Services\BankReconciliationService;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 10.6 (Sprint 10) — cloture-exercice.html → Livewire\Comptabilite\ClotureExercice
 * "Assistant de clôture d'exercice comptable (N → N+1)" — Document 01
 * §6.6, assistant à 3 étapes réelles, aucune approximée.
 *
 * ⚠️ Étape 1 (Travaux d'Inventaire) : le prototype la traite comme un
 * simple toast sans état persistant — corrigé (`fiscal_years.step1_confirmed_at`
 * réellement enregistré, ticket 10.6 addendum). Les travaux eux-mêmes
 * (rapprochements, amortissements, provisions, FNP/FAE) restent des
 * écritures manuelles réelles à passer par le Journal Comptable (ticket
 * 10.4) AVANT de confirmer cette étape — cet écran ne les invente pas,
 * il ne fait que tracer la confirmation que l'utilisateur les a faites.
 *
 * Étape 2 (Solde des Comptes de Gestion) : RÉEL — calcule le solde de
 * chaque compte de classe 6 (charges) et 7 (produits) sur l'exercice,
 * génère UNE écriture équilibrée qui solde chacun de ces comptes à zéro
 * avec pour contrepartie le compte 131 (Bénéfice) si résultat positif ou
 * 139 (Perte) si négatif — jamais une simulation, une vraie écriture
 * dans le grand livre.
 *
 * Étape 3 (Clôture définitive) : RÉEL — verrouille (`is_locked = true`)
 * TOUTES les écritures actives de l'exercice clôturé (irréversible,
 * fidèle à l'avertissement du prototype), crée le nouvel exercice
 * (statut ouvert), génère les écritures de report à nouveau (RAN) pour
 * les comptes de bilan (classes 1 à 5) au 1er janvier du nouvel exercice.
 *
 * ⚠️ CORRECTION CRITIQUE APPORTÉE À `AccountingEntryService` DANS CE
 * MÊME TICKET : `record()` recherchait auparavant "le dernier exercice
 * ouvert" sans vérifier que la DATE de l'écriture tombe réellement dans
 * cet exercice — une fois qu'un exercice peut être réellement clôturé
 * (ce ticket), une écriture antidatée aurait pu être rattachée à tort au
 * nouvel exercice. Corrigé pour résoudre l'exercice qui couvre
 * effectivement la date, et refuser toute écriture dont la date tombe
 * dans un exercice clos (Document 01 §6.6 point 4, `ClosedFiscalYearException`).
 *
 * "Lettrage Bancaire" (KPI) : 🔴→✅ LIVRÉ AU TICKET 14.43. Le mécanisme
 * manquait au projet entier, pas à cet écran ; il existe depuis le ticket
 * 14.8 (`BankReconciliationService`, import de relevé CSV, lettrage ligne
 * à ligne) sans que cette carte y soit jamais revenue. Le taux est
 * désormais calculé sur l'exercice sélectionné, les deux côtés confondus
 * (livre ET relevé). ⚠️ Aucun relevé importé ⇒ « — » et le motif, JAMAIS
 * 100 % : zéro ligne lettrée sur zéro n'est pas un rapprochement parfait,
 * et l'afficher ainsi autoriserait une clôture sur une trésorerie non
 * vérifiée.
 */
#[Layout('layouts.app')]
class ClotureExercice extends Component
{
    public string $selectedYear = '';

    /** Ticket 14.14 — onglet actif : 'periodique' (defaut, comme le prototype) ou 'annuelle'. */
    public string $tab = 'periodique';

    /** Mois vise par la cloture periodique, format YYYY-MM. */
    public string $periodeACloturer = '';

    /** Cloture visee par la decloture exceptionnelle. */
    public string $closureAReouvrir = '';

    public function mount(): void
    {
        $this->selectedYear = (string) (FiscalYear::current()?->year ?? now()->year);
        $this->periodeACloturer = now()->format('Y-m');
    }

    public function getFiscalYearProperty(): ?FiscalYear
    {
        return FiscalYear::where('year', $this->selectedYear)->first();
    }

    public function changeYear(int $delta): void
    {
        $this->selectedYear = (string) ((int) $this->selectedYear + $delta);
        $this->refreshComputed();
    }

    /**
     * 🔴→✅ TICKET 14.2 — BUG RÉEL CORRIGÉ : `fiscalYear` et `kpis` sont des
     * propriétés calculées, et Livewire les **mémoïse pour la durée de la
     * requête** (`SupportLegacyComputedPropertySyntax` : la valeur est
     * poussée dans `store($this)->find('computedProperties', ...)` au premier
     * accès). Une action qui LIT l'une d'elles puis MODIFIE les données
     * derrière laisse donc le rendu qui suit afficher la valeur d'AVANT
     * l'action.
     *
     * Symptôme réel observé (test `ClotureExerciceTest` — qui n'avait jamais
     * pu s'exécuter avant le ticket 14.1, faute de `tests/TestCase.php`) :
     * après un clic sur « Solder les comptes de gestion », l'écran continuait
     * d'annoncer « 2 comptes à solder » alors que l'écriture de solde était
     * bel et bien enregistrée et les comptes réellement soldés — l'opérateur
     * pouvait croire l'étape 2 en échec et la relancer.
     *
     * Toute action de cet écran qui change `selectedYear` ou écrit en base
     * appelle donc cette méthode : le rendu repart de l'état réel.
     */
    private function refreshComputed(): void
    {
        unset($this->fiscalYear, $this->kpis);
    }

    /** Solde de chaque compte de classe 6/7 sur l'exercice sélectionné — un seul point de calcul. */
    private function gestionBalances(): array
    {
        if (! $this->fiscalYear) {
            return [];
        }

        return AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
            ->where('accounting_entries.is_active', true)
            ->where('accounting_entries.fiscal_year_id', $this->fiscalYear->id)
            ->join('chart_of_accounts', 'chart_of_accounts.id', '=', 'accounting_entry_lines.account_id')
            ->whereIn('chart_of_accounts.class', [6, 7])
            ->selectRaw('chart_of_accounts.id as account_id, chart_of_accounts.class, SUM(accounting_entry_lines.debit) as total_debit, SUM(accounting_entry_lines.credit) as total_credit')
            ->groupBy('chart_of_accounts.id', 'chart_of_accounts.class')
            ->havingRaw('SUM(accounting_entry_lines.debit) <> SUM(accounting_entry_lines.credit)')
            ->get()
            ->map(fn ($l) => ['account_id' => $l->account_id, 'class' => (int) $l->class, 'balance' => round((float) $l->total_debit - (float) $l->total_credit, 2)])
            ->all();
    }

    public function getKpisProperty(): array
    {
        $balances = $this->gestionBalances();
        $charges = array_sum(array_map(fn ($b) => $b['class'] === 6 ? $b['balance'] : 0, $balances));
        $produits = array_sum(array_map(fn ($b) => $b['class'] === 7 ? -$b['balance'] : 0, $balances));

        $lettrage = $this->fiscalYear
            ? app(BankReconciliationService::class)->tauxDeLettrage(
                $this->fiscalYear->start_date->format('Y-m-d'),
                $this->fiscalYear->end_date->format('Y-m-d'),
            )
            : ['taux' => null, 'lignes' => 0, 'lettrees' => 0, 'comptes_sans_releve' => 0];

        return [
            'resultat' => round($produits - $charges, 2),
            'comptes_a_solder' => count($balances),
            'lettrage' => $lettrage,
        ];
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR VÉRIFICATION NIVEAU 2 : bouton "Exporter
     * PDF" totalement absent — réutilise `gestionBalances()` déjà réel
     * (un seul point de vérité pour "quels comptes sont à solder"),
     * enrichi avec les libellés de compte pour un export lisible.
     */
    public function exportClotureExercicePdf()
    {
        $this->authorize('view-comptabilite');

        $balances = $this->gestionBalances();
        $accountIds = array_column($balances, 'account_id');
        $accounts = \App\Models\ChartOfAccount::whereIn('id', $accountIds)->get()->keyBy('id');

        $rows = collect($balances)->map(fn ($b) => [
            'code' => $accounts[$b['account_id']]->code ?? '—',
            'label' => $accounts[$b['account_id']]->label ?? '—',
            'class' => $b['class'],
            'balance' => $b['balance'],
        ]);

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.cloture-exercice',
            ['rows' => $rows, 'fiscalYear' => $this->fiscalYear, 'kpis' => $this->kpis],
            "Bascule & Clôture d'Exercice Comptable",
            $this->fiscalYear ? 'Exercice '.$this->fiscalYear->year : ''
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'cloture-exercice-'.now()->format('Y-m-d').'.pdf');
    }

    /* ==================== CLÔTURE PÉRIODIQUE (ticket 14.14) ==================== */

    /**
     * Ticket 14.14 — Clôture Périodique : verrouillage mensuel léger.
     *
     * Onglet marqué « (nouveau) » dans le prototype source, jamais
     * implémenté. Distinct de la clôture ANNUELLE : il n'affecte pas le
     * Report à Nouveau et reste réversible par un Administrateur.
     *
     * ⚠️ LE VERROU EST RÉELLEMENT APPLIQUÉ — c'est le point qui fait la
     * différence entre une fonctionnalité et une liste décorative :
     * `JournalComptable::saveEntry()` refuse toute écriture, nouvelle ou
     * modifiée, dont la date tombe dans un mois clôturé. Sans ce contrôle,
     * clôturer un mois n'aurait strictement aucun effet.
     */
    public function getPeriodesCloturablesProperty(): array
    {
        return collect(range(0, 11))
            ->mapWithKeys(function ($i) {
                $date = now()->startOfMonth()->subMonths($i);

                return [$date->format('Y-m') => ucfirst($date->translatedFormat('F Y'))];
            })
            ->all();
    }

    public function getClosuresProperty()
    {
        return PeriodicClosure::with(['closedBy', 'reopenedBy'])->orderByDesc('period')->get();
    }

    /**
     * Balance du mois sélectionné — la clôture est REFUSÉE si Σdébit ≠ Σcrédit.
     * Contrôle serveur, jamais un simple affichage contournable.
     */
    public function getPeriodeBalanceProperty(): array
    {
        $debut = \Carbon\Carbon::createFromFormat('Y-m-d', $this->periodeACloturer.'-01')->startOfMonth();

        $balance = app(\App\Services\FinancialReportService::class)->balanceGenerale(
            $debut->format('Y-m-d'),
            $debut->copy()->endOfMonth()->format('Y-m-d')
        );

        return [
            'is_balanced' => $balance['is_balanced'],
            'ecart' => $balance['ecart'],
        ];
    }

    public function getPeriodeDejaClotureeProperty(): bool
    {
        return PeriodicClosure::where('period', $this->periodeACloturer)->whereNull('reopened_at')->exists();
    }

    public function cloturerPeriode(): void
    {
        $this->authorize('close-fiscal-year');

        if ($this->periodeDejaCloturee) {
            $this->dispatch('toast', message: 'Ce mois est déjà clôturé.', type: 'error');

            return;
        }

        // Contrôle serveur RÉEL : une balance déséquilibrée bloque la clôture.
        if (! $this->periodeBalance['is_balanced']) {
            $this->dispatch('toast', message: "Balance déséquilibrée (écart de {$this->periodeBalance['ecart']} FCFA) — corrigez l'écart avant de clôturer ce mois.", type: 'error');

            return;
        }

        PeriodicClosure::updateOrCreate(
            ['period' => $this->periodeACloturer],
            ['closed_at' => now(), 'closed_by' => Auth::id(), 'reopened_at' => null, 'reopened_by' => null],
        );

        AuditLog::record('periodic_closure.closed', 'comptabilite');
        $this->dispatch('close-modal', name: 'modal-confirm-cloture-periodique');
        $this->dispatch('toast', message: 'Mois clôturé — les écritures de cette période sont désormais verrouillées.', type: 'success');
        unset($this->closures, $this->periodeDejaCloturee);
    }

    /**
     * Déclôture EXCEPTIONNELLE — réservée à l'Administrateur (`manage-modules`,
     * la permission réellement admin-seul du seeder), tracée avec identité et
     * horodatage. La ligne n'est jamais supprimée : l'historique d'une action
     * exceptionnelle doit rester consultable.
     */
    public function decloturerPeriode(string $id): void
    {
        $this->authorize('manage-modules');

        $closure = PeriodicClosure::findOrFail($id);

        if (! $closure->isLocked()) {
            $this->dispatch('toast', message: "Ce mois n'est pas clôturé.", type: 'error');

            return;
        }

        $closure->update(['reopened_at' => now(), 'reopened_by' => Auth::id()]);

        AuditLog::record('periodic_closure.reopened', 'comptabilite');
        $this->dispatch('close-modal', name: 'modal-confirm-decloture');
        $this->dispatch('toast', message: "Mois déclôturé — action exceptionnelle journalisée dans les Logs d'Audit.", type: 'warning');
        unset($this->closures, $this->periodeDejaCloturee);
    }

    public function confirmStep1(): void
    {
        $this->authorize('close-fiscal-year');
        $year = $this->fiscalYear;
        if (! $year) {
            return;
        }

        $year->update(['step1_confirmed_at' => now()]);
        AuditLog::record('fiscal_year.step1_confirmed', 'comptabilite');
        $this->dispatch('toast', message: 'Étape 1 validée — rapprochements et régularisations confirmés.', type: 'success');
    }

    public function soldeComptesGestion(): void
    {
        $year = $this->fiscalYear;
        $balances = $this->gestionBalances();

        if (! $year || empty($balances)) {
            $this->dispatch('toast', message: 'Aucun compte de charges/produits à solder pour cet exercice.', type: 'warning');

            return;
        }

        $resultat = $this->kpis['resultat'];
        $resultAccount = ChartOfAccount::where('code', $resultat >= 0 ? '131' : '139')->first();

        if (! $resultAccount) {
            $this->dispatch('toast', message: "Compte 131/139 introuvable dans le plan comptable — créez-le avant de solder.", type: 'error');

            return;
        }

        // Chaque compte 6/7 est ramené à zéro (contrepartie inverse de son
        // solde), la ligne finale sur 131/139 absorbe le résultat net —
        // équilibre garanti par construction (la somme des soldes fermés = résultat).
        $lines = [];
        foreach ($balances as $b) {
            if ($b['balance'] > 0) {
                $lines[] = ['account_id' => $b['account_id'], 'debit' => 0, 'credit' => $b['balance']];
            } else {
                $lines[] = ['account_id' => $b['account_id'], 'debit' => abs($b['balance']), 'credit' => 0];
            }
        }
        $lines[] = $resultat >= 0
            ? ['account_id' => $resultAccount->id, 'debit' => 0, 'credit' => $resultat]
            : ['account_id' => $resultAccount->id, 'debit' => abs($resultat), 'credit' => 0];

        try {
            app(AccountingEntryService::class)->record(
                lines: $lines,
                entryDate: $year->end_date->format('Y-m-d'),
                reference: "Solde des comptes de gestion {$year->year}",
                sourceType: 'closing',
                sourceId: $year->id,
            );

            AuditLog::record('fiscal_year.gestion_accounts_closed', 'comptabilite');

            // Les comptes 6/7 viennent d'être soldés : `kpis` a été lu plus
            // haut (résultat net) et porte encore l'état d'avant l'écriture.
            $this->refreshComputed();

            $this->dispatch('toast', message: 'Comptes de charges et produits soldés — résultat net calculé : '.number_format($resultat, 0, ',', ' ').' FCFA.', type: 'success');
        } catch (\Throwable $e) {
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');
        }
    }

    public function confirmCloture(): void
    {
        $this->authorize('close-fiscal-year');
        $year = $this->fiscalYear;

        if (! $year || $year->status !== 'ouvert') {
            $this->dispatch('toast', message: 'Cet exercice ne peut pas être clôturé (déjà clos ou introuvable).', type: 'error');

            return;
        }

        DB::transaction(function () use ($year) {
            $newYearNumber = $year->year + 1;
            $newYear = FiscalYear::firstOrCreate(
                ['year' => $newYearNumber],
                [
                    'start_date' => "{$newYearNumber}-01-01",
                    'end_date' => "{$newYearNumber}-12-31",
                    'status' => 'ouvert',
                ]
            );

            // Report à nouveaux (RAN) — comptes de bilan (classes 1 à 5)
            // uniquement, reportés avec leur solde exact au 1er janvier N+1.
            $bilanBalances = AccountingEntryLine::query()
                ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
                ->where('accounting_entries.is_active', true)
                ->where('accounting_entries.fiscal_year_id', $year->id)
                ->join('chart_of_accounts', 'chart_of_accounts.id', '=', 'accounting_entry_lines.account_id')
                ->whereIn('chart_of_accounts.class', [1, 2, 3, 4, 5])
                ->selectRaw('chart_of_accounts.id as account_id, SUM(accounting_entry_lines.debit) as total_debit, SUM(accounting_entry_lines.credit) as total_credit')
                ->groupBy('chart_of_accounts.id')
                ->havingRaw('SUM(accounting_entry_lines.debit) <> SUM(accounting_entry_lines.credit)')
                ->get();

            if ($bilanBalances->isNotEmpty()) {
                $ranLines = $bilanBalances->map(function ($b) {
                    $balance = round((float) $b->total_debit - (float) $b->total_credit, 2);

                    return $balance > 0
                        ? ['account_id' => $b->account_id, 'debit' => $balance, 'credit' => 0]
                        : ['account_id' => $b->account_id, 'debit' => 0, 'credit' => abs($balance)];
                })->all();

                // Report à nouveaux équilibré par construction : la somme des
                // soldes de bilan reportés est nécessairement nulle (identité
                // comptable déjà démontrée pour le Bilan, ticket 10.5).
                app(AccountingEntryService::class)->record(
                    lines: $ranLines,
                    entryDate: $newYear->start_date->format('Y-m-d'),
                    reference: "Report à nouveaux — exercice {$newYear->year}",
                    sourceType: 'ran',
                    sourceId: $year->id,
                );
            }

            // Verrouillage définitif de l'exercice clôturé — TOUTES ses
            // écritures actives, irréversible.
            AccountingEntry::where('fiscal_year_id', $year->id)->update(['is_locked' => true]);

            $year->update([
                'status' => 'cloture',
                'closed_at' => now(),
                'closed_by' => Auth::id(),
            ]);

            AuditLog::record('fiscal_year.closed', 'comptabilite');
        });

        $this->dispatch('close-modal', name: 'modal-confirm-cloture');
        $this->dispatch('toast', message: "Exercice {$year->year} clôturé avec succès — exercice ".($year->year + 1).' ouvert.', type: 'success');
        $this->selectedYear = (string) ($year->year + 1);

        // 🔴→✅ TICKET 14.2 — 2e occurrence du MÊME défaut, cherchée
        // systématiquement plutôt que corrigée au cas par cas : `fiscalYear`
        // a été lu en début de méthode pour l'exercice N et resterait
        // mémoïsé, si bien que l'écran affichait encore l'exercice qui vient
        // d'être CLÔTURÉ au lieu du nouvel exercice N+1 qu'il annonce
        // pourtant dans son propre message de succès.
        $this->refreshComputed();
    }

    public function render()
    {
        return view('livewire.comptabilite.cloture-exercice', ['title' => 'Comptabilité > Clôture Exercice']);
    }
}
