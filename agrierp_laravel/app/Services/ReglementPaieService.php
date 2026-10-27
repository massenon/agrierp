<?php

namespace App\Services;

use App\Actions\RecordPayrollAccountingEntryAction;
use App\Exceptions\ClosedFiscalYearException;
use App\Exceptions\NoOpenFiscalYearException;
use App\Models\AttendanceRecord;
use App\Models\AuditLog;
use App\Models\Employee;
use App\Models\Payslip;
use App\Models\TreasuryAccount;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Ticket RH-4 — POINT DE PASSAGE UNIQUE du règlement d'une paie : le web (`GestionPaie::validerReglement`) et la
 * demande d'un poste (`SyncController::pushPayslipRequests`) passent ici.
 *
 * Un règlement = UNE transaction : bulletin (`payslips`), décrément du premier compte de trésorerie actif, écriture
 * SYSCOHADA (`RecordPayrollAccountingEntryAction` : 661 au débit), audit `payslip.paid`. Les règles d'exercice (EX5,
 * décision Q4 du 20/10/2026) sont vérifiées AVANT toute écriture : la charge est datée du dernier jour de la période
 * payée, jamais après le règlement ; les deux dates doivent tomber dans un exercice OUVERT.
 *
 * ⚠️ Le poste n'envoie que la DEMANDE (employé, période, instant du clic) : ni montant, ni compte, ni écriture. Le
 * calcul est celui de `PayrollCalculationService`, ici — un net « vu au poste » ne fait jamais foi.
 */
class ReglementPaieService
{
    public const MESSAGE_DEJA_REGLEE = 'La paie de cette période est déjà réglée pour cet employé.';

    public const MESSAGE_EMPLOYE_ARCHIVE = 'Cet employé est archivé : sa paie ne peut plus être réglée.';

    public function __construct(
        private readonly PayrollCalculationService $calcul,
        private readonly AccountingEntryService $ecritures,
        private readonly RecordPayrollAccountingEntryAction $ecriturePaie,
    ) {}

    /** Jours d'absence RETENUS sur une période : pointages `absent` ACTIFS du mois (un pointage archivé ne retient rien). */
    public static function joursAbsence(Employee $employe, string $periode): int
    {
        return AttendanceRecord::where('employee_id', $employe->id)
            ->where('status', 'absent')
            ->where('is_active', true)
            ->whereYear('attendance_date', substr($periode, 0, 4))
            ->whereMonth('attendance_date', substr($periode, 5, 2))
            ->count();
    }

    /**
     * Ticket EX5 (Q4) — date de la charge d'une paie : le dernier jour de la période payée, sauf si le règlement a lieu
     * avant (paie du mois en cours réglée avant sa fin) — jamais une charge datée APRÈS son règlement ni dans le futur.
     */
    public static function dateDeLaCharge(string $periode, Carbon $reglement): string
    {
        $finDePeriode = Carbon::parse($periode)->endOfMonth()->format('Y-m-d');

        return min($finDePeriode, $reglement->format('Y-m-d'));
    }

    /**
     * Règle la paie d'un employé pour une période (`AAAA-MM-01`).
     *
     * @return array{payslip: Payslip, deja: bool, ecriture_manquante: bool}
     *
     * @throws NoOpenFiscalYearException|ClosedFiscalYearException  exercice de la charge ou du règlement fermé / absent
     * @throws \App\Exceptions\ReglementPaieRefuseException  employé archivé
     */
    public function valider(Employee $employe, string $periode, ?Carbon $reglement = null): array
    {
        $reglement ??= now();
        $periode = Carbon::parse($periode)->startOfMonth()->format('Y-m-d');

        $existing = Payslip::where('employee_id', $employe->id)->whereDate('period_month', $periode)->first();
        if ($existing) {
            return ['payslip' => $existing, 'deja' => true, 'ecriture_manquante' => false];
        }

        if (! $employe->is_active) {
            throw new \App\Exceptions\ReglementPaieRefuseException(self::MESSAGE_EMPLOYE_ARCHIVE);
        }

        $dateCharge = self::dateDeLaCharge($periode, $reglement);
        $dateReglement = $reglement->format('Y-m-d');

        // Contrôlé AVANT toute écriture : ni bulletin, ni trésorerie, ni écriture.
        $this->ecritures->exerciceOuvertPour($dateCharge);
        $this->ecritures->exerciceOuvertPour($dateReglement);

        $brut = (float) ($employe->base_salary ?? 0);
        $calcul = $this->calcul->calculer($brut, self::joursAbsence($employe, $periode));

        return DB::transaction(function () use ($employe, $periode, $brut, $calcul, $dateCharge, $dateReglement) {
            $payslip = Payslip::create([
                'employee_id' => $employe->id,
                'period_month' => $periode,
                'gross_salary' => $brut,
                'absence_deduction' => $calcul['retenue_absence'],
                'cnss_deduction' => $calcul['cnss_salariale'],
                // Retenue salariale : diminue le net versé.
                'its_deduction' => $calcul['its'],
                // Charges patronales : payées EN PLUS, ne touchent pas le net.
                'vps_employer' => $calcul['vps'],
                'cnss_employer_pension' => $calcul['cnss_patronale_pension'],
                'cnss_employer_family' => $calcul['cnss_patronale_famille'],
                'cnss_employer_risk' => $calcul['cnss_patronale_risque'],
                'net_salary' => $calcul['net'],
            ]);

            // Décrément réel de trésorerie à la validation — le premier compte actif (simplification documentée).
            $account = TreasuryAccount::where('is_active', true)->first();
            if ($account) {
                $account->decrement('balance', $calcul['net']);
            }

            // 🔴→✅ TICKET 14.25 — ÉCRITURE COMPTABLE : la charge portée au débit est le salaire RÉELLEMENT DÛ.
            $ecriture = $this->ecriturePaie->execute($payslip, $account?->id, $dateCharge, $dateReglement);
            AuditLog::record('payslip.paid', 'rh');
            if ($ecriture === null) {
                // Jamais silencieux — même discipline que le POS et les Achats.
                AuditLog::record('payslip.accounting_entry_missing', 'comptabilite');
            }

            return ['payslip' => $payslip, 'deja' => false, 'ecriture_manquante' => $ecriture === null];
        });
    }
}
