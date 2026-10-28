<?php

namespace App\Services;

use App\Actions\ReopenFiscalYearAction;
use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\PeriodicClosure;
use Illuminate\Support\Facades\DB;

/**
 * Ticket CP-4 — POINT DE PASSAGE UNIQUE DE LA CLÔTURE (périodes et exercice).
 *
 * Appelé par `Comptabilite\ClotureExercice` et `Parametres\AssistantDemarrage` (le web) ET par l'envoi du poste
 * (`SyncController::pushFiscalClosureRequests`) : mêmes gardes, mêmes écritures, mêmes messages, mêmes audits.
 * Le DROIT n'est pas jugé ici : il l'est par l'appelant (`close-fiscal-year`, `manage-modules`, `manage-comptabilite`).
 *
 * ⚠️ Toute méthode qui refuse lève une `\DomainException` dont le message est le motif en clair affiché tel quel (toast web,
 * motif de la demande refusée au poste). Rien n'est écrit quand elle est levée.
 */
class ClotureExerciceService
{
    public const MOTIF_RIEN_A_SOLDER = 'Aucun compte de charges/produits à solder pour cet exercice.';

    /** Solde de chaque compte de classe 6/7 de l'exercice — un seul point de calcul. */
    public function soldesDeGestion(?FiscalYear $year): array
    {
        if (! $year) {
            return [];
        }

        return AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
            ->where('accounting_entries.is_active', true)
            ->where('accounting_entries.fiscal_year_id', $year->id)
            ->join('chart_of_accounts', 'chart_of_accounts.id', '=', 'accounting_entry_lines.account_id')
            ->whereIn('chart_of_accounts.class', [6, 7])
            ->selectRaw('chart_of_accounts.id as account_id, chart_of_accounts.class, SUM(accounting_entry_lines.debit) as total_debit, SUM(accounting_entry_lines.credit) as total_credit')
            ->groupBy('chart_of_accounts.id', 'chart_of_accounts.class')
            ->havingRaw('SUM(accounting_entry_lines.debit) <> SUM(accounting_entry_lines.credit)')
            ->get()
            ->map(fn ($l) => ['account_id' => $l->account_id, 'class' => (int) $l->class, 'balance' => round((float) $l->total_debit - (float) $l->total_credit, 2)])
            ->all();
    }

    /** Résultat provisoire (produits − charges) et nombre de comptes de gestion à solder. */
    public function indicateurs(?FiscalYear $year): array
    {
        $balances = $this->soldesDeGestion($year);
        $charges = array_sum(array_map(fn ($b) => $b['class'] === 6 ? $b['balance'] : 0, $balances));
        $produits = array_sum(array_map(fn ($b) => $b['class'] === 7 ? -$b['balance'] : 0, $balances));

        return ['resultat' => round($produits - $charges, 2), 'comptes_a_solder' => count($balances)];
    }

    /**
     * Soldes des comptes de bilan (classes 1 à 5) de l'exercice, tels que l'à-nouveau de N+1 les reportera.
     *
     * @return array<int, array{account_id: string, debit: float, credit: float}>
     */
    public function lignesDAnouveau(FiscalYear $year): array
    {
        return AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
            ->where('accounting_entries.is_active', true)
            ->where('accounting_entries.fiscal_year_id', $year->id)
            ->join('chart_of_accounts', 'chart_of_accounts.id', '=', 'accounting_entry_lines.account_id')
            ->whereIn('chart_of_accounts.class', [1, 2, 3, 4, 5])
            ->selectRaw('chart_of_accounts.id as account_id, SUM(accounting_entry_lines.debit) as total_debit, SUM(accounting_entry_lines.credit) as total_credit')
            ->groupBy('chart_of_accounts.id')
            ->havingRaw('SUM(accounting_entry_lines.debit) <> SUM(accounting_entry_lines.credit)')
            ->get()
            ->map(function ($b) {
                $balance = round((float) $b->total_debit - (float) $b->total_credit, 2);

                return $balance > 0
                    ? ['account_id' => $b->account_id, 'debit' => $balance, 'credit' => 0.0]
                    : ['account_id' => $b->account_id, 'debit' => 0.0, 'credit' => abs($balance)];
            })
            ->filter(fn ($l) => $l['debit'] > 0 || $l['credit'] > 0)
            ->values()
            ->all();
    }

    /**
     * 🔴→✅ TICKET EX4 (EF4) — POURQUOI L'ÉTAPE 3 EST REFUSÉE, ou `null` si la clôture est admise. Dans l'ordre :
     *  1. l'échéance (`end_date`) doit être passée ;
     *  2. N-1, s'il existe, doit être clos ;
     *  3. l'étape 1 doit être confirmée ;
     *  4. l'étape 2 doit être faite : plus aucun compte de classe 6 ou 7 ne porte de solde ;
     *  5. l'à-nouveau calculé doit être équilibré.
     * Le même motif grise le bouton à l'écran (web et poste) et refuse l'appel au serveur.
     */
    public function motifRefusCloture(?FiscalYear $year): ?string
    {
        if (! $year || $year->status !== 'ouvert') {
            return 'Cet exercice ne peut pas être clôturé (déjà clos ou introuvable).';
        }

        $echeance = $year->end_date->copy()->endOfDay();
        if (now()->lte($echeance)) {
            return "L'exercice {$year->year} ne peut être clôturé qu'après son échéance du {$year->end_date->format('d/m/Y')}, à partir du "
                .$year->end_date->copy()->addDay()->format('d/m/Y').'.';
        }

        $precedent = FiscalYear::where('year', $year->year - 1)->first();
        if ($precedent !== null && $precedent->status === 'ouvert') {
            return "L'exercice {$precedent->year} est encore ouvert : clôturez-le avant l'exercice {$year->year}.";
        }

        if (! $year->step1_confirmed_at) {
            return "Étape 1 non confirmée : marquez les travaux d'inventaire de {$year->year} comme terminés avant de clôturer.";
        }

        $aSolder = count($this->soldesDeGestion($year));
        if ($aSolder > 0) {
            return "Étape 2 non faite : {$aSolder} compte(s) de charges ou de produits de {$year->year} restent à solder. "
                .'Lancez « Calculer et Solder » avant de clôturer.';
        }

        $lignes = $this->lignesDAnouveau($year);
        $debit = round(array_sum(array_column($lignes, 'debit')), 2);
        $credit = round(array_sum(array_column($lignes, 'credit')), 2);
        if (abs($debit - $credit) >= 0.01) {
            $f = fn (float $m) => number_format($m, 0, ',', ' ').' F';

            return "L'à-nouveau de l'exercice ".($year->year + 1)." serait déséquilibré (débit {$f($debit)}, crédit {$f($credit)}) : "
                ."les comptes de bilan de {$year->year} ne s'équilibrent pas. Corrigez l'écart au Journal Comptable avant de clôturer.";
        }

        return null;
    }

    /** L'exercice de l'année [$annee], ou le motif « inexistant » (demande du poste). */
    public function exercice(int $annee): FiscalYear
    {
        return FiscalYear::where('year', $annee)->first()
            ?? throw new \DomainException("Aucun exercice {$annee} n'existe.");
    }

    /* ==================== CLÔTURE PÉRIODIQUE (ticket 14.14) ==================== */

    /** Balance du mois (AAAA-MM) : la clôture est REFUSÉE si Σdébit ≠ Σcrédit. */
    public function balanceDePeriode(string $periode): array
    {
        $debut = \Carbon\Carbon::createFromFormat('Y-m-d', $periode.'-01')->startOfMonth();

        $balance = app(FinancialReportService::class)->balanceGenerale(
            $debut->format('Y-m-d'),
            $debut->copy()->endOfMonth()->format('Y-m-d')
        );

        return ['is_balanced' => $balance['is_balanced'], 'ecart' => $balance['ecart']];
    }

    public function periodeDejaCloturee(string $periode): bool
    {
        return PeriodicClosure::where('period', $periode)->whereNull('reopened_at')->exists();
    }

    /** @throws \DomainException */
    public function cloturerPeriode(string $periode, ?string $userId = null): void
    {
        if (! preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $periode)) {
            throw new \DomainException('Mois à clôturer illisible (attendu : AAAA-MM).');
        }

        if ($this->periodeDejaCloturee($periode)) {
            throw new \DomainException('Ce mois est déjà clôturé.');
        }

        // Contrôle serveur RÉEL : une balance déséquilibrée bloque la clôture.
        $balance = $this->balanceDePeriode($periode);
        if (! $balance['is_balanced']) {
            throw new \DomainException("Balance déséquilibrée (écart de {$balance['ecart']} FCFA) — corrigez l'écart avant de clôturer ce mois.");
        }

        PeriodicClosure::updateOrCreate(
            ['period' => $periode],
            ['closed_at' => now(), 'closed_by' => $userId ?? auth()->id(), 'reopened_at' => null, 'reopened_by' => null],
        );

        AuditLog::record('periodic_closure.closed', 'comptabilite');
    }

    /**
     * Déclôture EXCEPTIONNELLE d'un mois (la ligne n'est jamais supprimée : l'historique reste consultable).
     *
     * @throws \DomainException
     */
    public function decloturerPeriode(PeriodicClosure $closure, ?string $userId = null): void
    {
        if (! $closure->isLocked()) {
            throw new \DomainException("Ce mois n'est pas clôturé.");
        }

        $closure->update(['reopened_at' => now(), 'reopened_by' => $userId ?? auth()->id()]);

        AuditLog::record('periodic_closure.reopened', 'comptabilite');
    }

    /* ==================== EXERCICE ==================== */

    /** Étape 1 — les travaux d'inventaire sont déclarés terminés. */
    public function confirmerEtape1(FiscalYear $year): void
    {
        $year->update(['step1_confirmed_at' => now()]);
        AuditLog::record('fiscal_year.step1_confirmed', 'comptabilite');
    }

    /**
     * Étape 2 — UNE écriture équilibrée solde chaque compte 6/7 à zéro, contrepartie 131 (bénéfice) ou 139 (perte).
     * Rend le résultat net.
     *
     * @throws \DomainException  rien à solder, compte 131/139 absent, écriture refusée
     */
    public function soldeComptesGestion(FiscalYear $year): float
    {
        $balances = $this->soldesDeGestion($year);

        if (empty($balances)) {
            throw new \DomainException(self::MOTIF_RIEN_A_SOLDER);
        }

        $resultat = $this->indicateurs($year)['resultat'];
        $resultAccount = ChartOfAccount::where('code', $resultat >= 0 ? '131' : '139')->first();

        if (! $resultAccount) {
            throw new \DomainException('Compte 131/139 introuvable dans le plan comptable — créez-le avant de solder.');
        }

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
        } catch (\Throwable $e) {
            // Ticket U5 : le motif d'une exception du framework (SQL…) n'est pas montré en anglais.
            throw new \DomainException(\App\Support\MessagesErreurFr::pourUtilisateur($e), 0, $e);
        }

        AuditLog::record('fiscal_year.gestion_accounts_closed', 'comptabilite');

        return $resultat;
    }

    /**
     * Étape 3 — clôture définitive : gardes (EX4), N+1 repris ou créé, à-nouveau, verrouillage, statut — en UNE transaction.
     *
     * @throws \DomainException  le motif de `motifRefusCloture`, ou celui de l'exception comptable (EX5) : rien n'est écrit
     */
    public function cloturerExercice(FiscalYear $year, ?string $userId = null): void
    {
        $refus = $this->motifRefusCloture($year);
        if ($refus !== null) {
            throw new \DomainException($refus);
        }

        try {
            DB::transaction(fn () => $this->cloturer($year, $userId));
        } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException|\App\Exceptions\UnbalancedAccountingEntryException $e) {
            // Ticket EX5 (EF6) — jamais une erreur 500 : rien n'est écrit (transaction annulée), le motif est dit.
            throw new \DomainException($e->getMessage(), 0, $e);
        }
    }

    private function cloturer(FiscalYear $year, ?string $userId): void
    {
        $newYearNumber = $year->year + 1;
        // Ticket EX3 — N+1 a d'ordinaire déjà été ouvert : il est repris, jamais recréé (`year` est unique).
        $newYear = FiscalYear::firstOrCreate(
            ['year' => $newYearNumber],
            [
                'start_date' => "{$newYearNumber}-01-01",
                'end_date' => "{$newYearNumber}-12-31",
                'status' => 'ouvert',
            ]
        );

        // Report à nouveaux (RAN) — comptes de bilan (classes 1 à 5) reportés avec leur solde exact au 1er janvier N+1.
        $ranLines = $this->lignesDAnouveau($year);

        if ($ranLines !== []) {
            app(AccountingEntryService::class)->record(
                lines: $ranLines,
                entryDate: $newYear->start_date->format('Y-m-d'),
                reference: "Report à nouveaux — exercice {$newYear->year}",
                sourceType: 'ran',
                sourceId: $year->id,
            );
        }

        // Verrouillage définitif de l'exercice clôturé — TOUTES ses écritures actives (🔁 15.53 : réversible).
        AccountingEntry::where('fiscal_year_id', $year->id)->update(['is_locked' => true]);

        $year->update([
            'status' => 'cloture',
            'closed_at' => now(),
            'closed_by' => $userId ?? auth()->id(),
        ]);

        AuditLog::record('fiscal_year.closed', 'comptabilite');
    }

    /** Réouverture exceptionnelle (ticket 15.53) — la logique vit dans `ReopenFiscalYearAction`. @throws \DomainException */
    public function rouvrirExercice(FiscalYear $year): void
    {
        app(ReopenFiscalYearAction::class)->execute($year);
    }

    /** Ticket EX3 — ouverture de N+1 par le bouton (dès le 1er décembre de N). @throws \DomainException */
    public function ouvrirExerciceSuivant(int $annee): FiscalYear
    {
        return app(OuvertureExerciceService::class)->ouvrir($annee, OuvertureExerciceService::BOUTON);
    }

    /**
     * Ticket 15.51 — le PREMIER exercice de la ferme (assistant de démarrage) : l'année civile en cours (règle de
     * `FiscalYearSeeder`). [$annee] n'est donné que par une demande du poste : ce ne peut être que l'année en cours.
     *
     * @throws \DomainException
     */
    public function ouvrirPremierExercice(?int $annee = null): FiscalYear
    {
        $courante = (int) now()->format('Y');
        $annee ??= $courante;

        if ($annee !== $courante) {
            throw new \DomainException("L'exercice {$annee} n'est pas celui de l'année en cours ({$courante}).");
        }

        $existant = FiscalYear::where('year', $annee)->first();
        if ($existant !== null) {
            throw new \DomainException($existant->status === 'cloture'
                ? "L'exercice {$annee} est clôturé : une clôture est définitive."
                : "L'exercice {$annee} existe déjà.");
        }

        $exercice = FiscalYear::create([
            'year' => $annee,
            'start_date' => "{$annee}-01-01",
            'end_date' => "{$annee}-12-31",
            'status' => 'ouvert',
        ]);
        AuditLog::record('fiscal_year.opened', 'comptabilite');

        return $exercice;
    }
}
