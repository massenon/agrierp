<?php

namespace App\Actions;

use App\Models\AccountingEntry;
use App\Models\AuditLog;
use App\Models\PeriodicClosure;
use App\Services\AccountingEntryService;
use Illuminate\Validation\ValidationException;

/**
 * Ticket CP-2 — POINT DE PASSAGE UNIQUE DE L'ÉCRITURE MANUELLE (créer, modifier, archiver une opération diverse).
 *
 * Appelé par `Comptabilite\JournalComptable` (le web) ET par l'envoi du poste (`SyncController::pushManualEntryRequests`,
 * droit `manage-comptabilite`) : mêmes contrôles, mêmes messages, mêmes traces d'audit. L'écriture elle-même passe par
 * `AccountingEntryService` (`recordManual`, `updateManual`, `archiver`) — exercice ouvert, mois non clôturé, écriture non
 * verrouillée, débit ≠ crédit.
 *
 * ⚠️ IDEMPOTENCE : une création du poste porte l'UUID de sa demande, posé en `source_id` de l'écriture (`source_type`
 * `manual`) ; la rejouer rend l'écriture existante sans en créer une seconde. Archiver une écriture déjà archivée ne laisse
 * aucune seconde trace.
 */
class SaisieEcritureManuelleAction
{
    public function __construct(private readonly AccountingEntryService $service) {}

    public function creer(string $debitAccountId, string $creditAccountId, float $montant, string $date, string $libelle, ?string $demandeId = null): AccountingEntry
    {
        if ($demandeId !== null) {
            $existante = AccountingEntry::where('source_type', 'manual')->where('source_id', $demandeId)->first();
            if ($existante !== null) {
                return $existante;
            }
        }

        $this->controler($debitAccountId, $creditAccountId, $date);

        $ecriture = $this->service->recordManual(
            $debitAccountId,
            $creditAccountId,
            $montant,
            $date,
            AccountingEntry::generateReference().' — '.$libelle,
            sourceId: $demandeId,
        );
        AuditLog::record('accounting_entry.created', 'comptabilite');

        return $ecriture;
    }

    public function modifier(AccountingEntry $ecriture, string $debitAccountId, string $creditAccountId, float $montant, string $date, string $libelle): AccountingEntry
    {
        $this->controler($debitAccountId, $creditAccountId, $date);

        $numero = trim(explode('—', (string) $ecriture->reference, 2)[0]);
        $this->service->updateManual($ecriture, $debitAccountId, $creditAccountId, $montant, $date, $numero.' — '.$libelle);
        AuditLog::record('accounting_entry.updated', 'comptabilite');

        return $ecriture;
    }

    public function archiver(AccountingEntry $ecriture): void
    {
        if (! $ecriture->is_active) {
            return;
        }

        $this->service->archiver($ecriture);
        AuditLog::record('accounting_entry.archived', 'comptabilite', null, $ecriture);
    }

    /** @throws ValidationException le motif est celui que le web affiche sous le champ concerné */
    private function controler(string $debitAccountId, string $creditAccountId, string $date): void
    {
        if ($debitAccountId === $creditAccountId) {
            throw ValidationException::withMessages(['creditAccountId' => 'Le compte à créditer doit être différent du compte à débiter.']);
        }

        // 🔴→✅ TICKET 14.14 — APPLICATION RÉELLE DE LA CLÔTURE PÉRIODIQUE : vaut pour une création comme pour une modification.
        if (PeriodicClosure::isDateLocked($date)) {
            throw ValidationException::withMessages(['entryDate' => 'Ce mois est clôturé — aucune écriture ne peut y être ajoutée ni modifiée. Un Administrateur peut le déclôturer exceptionnellement.']);
        }
    }
}
