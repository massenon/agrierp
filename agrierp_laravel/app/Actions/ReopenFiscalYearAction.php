<?php

namespace App\Actions;

use App\Models\AccountingEntry;
use App\Models\AuditLog;
use App\Models\FiscalYear;
use App\Services\AccountingEntryService;
use Illuminate\Support\Facades\DB;

/**
 * Ticket 15.53 — RÉOUVERTURE D'UN EXERCICE CLÔTURÉ (décision client du 17/10/2026 : « si un exercice est
 * clôturé, on peut le rouvrir »).
 *
 * Défait exactement ce que la clôture (`ClotureExercice::confirmCloture`) a fait, sans rien effacer :
 *  1. le report à nouveau (écriture `ran` passée au 1er jour de N+1) est CONTRE-PASSÉ par une écriture inverse
 *     `ran_reversal` à la même date — il reste lisible au journal, et la prochaine clôture en passera un nouveau
 *     sur les soldes corrigés ;
 *  2. les écritures de N sont déverrouillées (`is_locked = false`, horodatées pour que les postes le tirent) ;
 *  3. N repasse « ouvert » ; l'exercice N+1 créé par la clôture reste ouvert.
 *
 * ⚠️ REFUS : un exercice qui n'est pas clôturé, ou dont l'exercice suivant est lui-même clôturé (rouvrir N
 * fausserait l'à-nouveau déjà verrouillé de N+1 : rouvrir N+1 d'abord). L'écriture `closing` (solde des comptes
 * de gestion, datée du 31/12 de N) reste : elle appartient à N, et une nouvelle clôture ne solde que l'écart.
 */
class ReopenFiscalYearAction
{
    public function execute(FiscalYear $exercice): void
    {
        if ($exercice->status !== 'cloture') {
            throw new \DomainException("L'exercice {$exercice->year} n'est pas clôturé.");
        }

        $suivant = FiscalYear::where('year', $exercice->year + 1)->first();
        if ($suivant?->status === 'cloture') {
            throw new \DomainException(
                "L'exercice ".($exercice->year + 1)." est clôturé : rouvrez-le d'abord, son report à nouveau dépend de {$exercice->year}."
            );
        }

        DB::transaction(function () use ($exercice) {
            $reports = AccountingEntry::with('lines')
                ->where('source_type', 'ran')
                ->where('source_id', $exercice->id)
                ->where('is_active', true)
                ->get();

            foreach ($reports as $report) {
                $dejaContrePasse = AccountingEntry::where('source_type', 'ran_reversal')
                    ->where('source_id', $report->id)->exists();
                if ($dejaContrePasse) {
                    continue;
                }

                app(AccountingEntryService::class)->record(
                    lines: $report->lines->map(fn ($l) => [
                        'account_id' => $l->account_id,
                        'debit' => (float) $l->credit,
                        'credit' => (float) $l->debit,
                    ])->all(),
                    entryDate: $report->entry_date->format('Y-m-d'),
                    reference: "Contre-passation du report à nouveau — réouverture de l'exercice {$exercice->year}",
                    sourceType: 'ran_reversal',
                    sourceId: $report->id,
                );
            }

            AccountingEntry::where('fiscal_year_id', $exercice->id)
                ->where('is_locked', true)
                ->update(['is_locked' => false, 'updated_at' => now()]);

            $exercice->update(['status' => 'ouvert', 'closed_at' => null, 'closed_by' => null]);
        });

        AuditLog::record('fiscal_year.reopened', 'comptabilite');
    }
}
