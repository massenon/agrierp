<?php

namespace App\Livewire\RH;

use App\Models\AttendanceRecord;
use App\Models\AuditLog;
use App\Models\Employee;
use App\Models\Payslip;
use App\Services\PayrollCalculationService;
use App\Actions\RecordPayrollAccountingEntryAction;
use App\Models\TreasuryAccount;
use Illuminate\Support\Facades\DB;
use Livewire\Component;

/**
 * gestion-paie.html → Livewire\RH\GestionPaie
 * "Calcul automatique des retenues croisées avec la Feuille de
 * Pointage."
 *
 * FORMULE VÉRIFIÉE MOT POUR MOT contre le texte affiché sur le
 * prototype lui-même (bandeau d'information, pas une description
 * générique d'un document externe) :
 *   Retenue Absences = (Salaire Brut ÷ 26 jours ouvrés) × Jours
 *   d'absence non justifiée [= `attendance_records.status = 'absent'`
 *   sur le mois, jamais 'conge' qui est une absence justifiée].
 *   Retenue CNSS = Salaire Brut × 3.6% (toujours appliquée).
 *   Net à Payer = Brut − Retenue Absences − Retenue CNSS.
 * Contre-vérifiée sur les 5 lignes du prototype : DOSSOU Marcelin
 * (75000÷26)×2 = 5 769 ✓, KPOSSOU Éléonore (80000÷26)×1 = 3 077 ✓.
 *
 * Statut Payé/En attente dérivé de l'EXISTENCE d'un `Payslip` persisté
 * pour cet employé/ce mois — pas un champ séparé qui pourrait diverger.
 * Tant qu'aucun `Payslip` n'existe, le calcul reste live (aperçu avant
 * validation) ; "Valider le règlement" persiste réellement le bulletin
 * ET décrémente la trésorerie (mémoire du projet : la validation d'un
 * bulletin doit faire sortir l'argent réellement, jamais un simple
 * changement de statut sans effet financier).
 *
 * ⚠️ Aucun sélecteur de compte de trésorerie dans le prototype
 * ("Valider le règlement" est une action en un clic, sans modale) — le
 * premier compte de trésorerie actif est débité par défaut plutôt que
 * de forcer une étape supplémentaire absente du prototype. Simplification
 * documentée, pas un oubli.
 *
 * 🔴→✅ EXTENSION DU PATTERN RBAC CRUD AU NIVEAU ACTION (référence
 * initiale : `PlanComptable`) — `$this->authorize('manage-rh')` sur
 * `validerReglement()`, qui décrémente réellement la trésorerie. Action
 * financière sensible, jamais accessible à un futur rôle personnalisé en
 * lecture seule sur le module RH.
 */
class GestionPaie extends Component
{
    public string $periodMonth = '';

    public function mount(): void
    {
        $this->periodMonth = now()->format('Y-m');
    }

    private function periodDate(): string
    {
        return $this->periodMonth.'-01';
    }

    public function getRowsProperty()
    {
        $employees = Employee::where('is_active', true)->orderBy('last_name')->get();
        $period = $this->periodDate();

        return $employees->map(function ($employee) use ($period) {
            $existing = Payslip::where('employee_id', $employee->id)->whereDate('period_month', $period)->first();

            if ($existing) {
                return [
                    'employee' => $employee,
                    'payslip' => $existing,
                    'gross' => (float) $existing->gross_salary,
                    'absence_days' => null,
                    'absence_deduction' => (float) $existing->absence_deduction,
                    'cnss_deduction' => (float) $existing->cnss_deduction,
                    // Ticket 14.38 — retenue ITS et charges patronales.
                    'its_deduction' => (float) ($existing->its_deduction ?? 0),
                    'charges_patronales' => round(
                        (float) ($existing->vps_employer ?? 0)
                        + (float) ($existing->cnss_employer_pension ?? 0)
                        + (float) ($existing->cnss_employer_family ?? 0)
                        + (float) ($existing->cnss_employer_risk ?? 0),
                        2
                    ),
                    'net' => (float) $existing->net_salary,
                    'paid' => true,
                ];
            }

            $gross = (float) ($employee->base_salary ?? 0);
            $absenceDays = AttendanceRecord::where('employee_id', $employee->id)
                ->where('status', 'absent')
                ->where('is_active', true)   // un pointage archivé ne retient plus d'absence sur la paie
                ->whereYear('attendance_date', substr($period, 0, 4))
                ->whereMonth('attendance_date', substr($period, 5, 2))
                ->count();

            // 🔴→✅ TICKET 14.38 — MÊME SERVICE QUE LE RÈGLEMENT.
            //
            // La prévisualisation recalculait le net avec un taux CNSS écrit en
            // dur, sans ITS ni charges patronales : l'écran annonçait donc un
            // net supérieur à celui réellement versé au moment de valider. Deux
            // formules pour un même bulletin finissent toujours par diverger.
            $calcul = app(PayrollCalculationService::class)->calculer($gross, $absenceDays);

            return [
                'employee' => $employee,
                'payslip' => null,
                'gross' => $gross,
                'absence_days' => $absenceDays,
                'absence_deduction' => $calcul['retenue_absence'],
                'cnss_deduction' => $calcul['cnss_salariale'],
                'its_deduction' => $calcul['its'],
                'charges_patronales' => $calcul['total_charges_patronales'],
                'net' => $calcul['net'],
                'paid' => false,
                // Rendu VISIBLE : un ITS nul faute de barème n'est pas un ITS
                // nul parce que le salaire est sous le seuil d'imposition.
                'bareme_its_renseigne' => $calcul['bareme_its_renseigne'],
            ];
        });
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR COMPARAISON STRUCTURELLE RIGOUREUSE : le
     * bouton "Exporter" du prototype (Livre de Paie) était totalement
     * absent — même schéma déjà trouvé sur plusieurs écrans RH/Ventes/
     * Achats/Stocks.
     */
    public function exportLivrePaiePdf()
    {
        $this->authorize('view-rh');

        $rows = $this->rows;

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.gestion-paie',
            ['rows' => $rows, 'period' => $this->periodDate()],
            'Livre de Paie',
            'Période : '.\Carbon\Carbon::parse($this->periodDate())->translatedFormat('F Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'livre-paie-'.now()->format('Y-m-d').'.pdf');
    }

    public function getKpisProperty(): array
    {
        $rows = $this->rows;

        return [
            'masse_salariale' => $rows->sum('gross'),
            'bulletins_emis' => $rows->where('paid', true)->count(),
            'charges_cnss' => $rows->sum('cnss_deduction'),
            'en_attente' => $rows->where('paid', false)->count(),
        ];
    }

    public function validerReglement(string $employeeId): void
    {
        $this->authorize('manage-rh');

        $employee = Employee::findOrFail($employeeId);
        $period = $this->periodDate();

        $existing = Payslip::where('employee_id', $employee->id)->whereDate('period_month', $period)->first();

        if ($existing) {
            return;
        }

        $gross = (float) ($employee->base_salary ?? 0);
        $absenceDays = AttendanceRecord::where('employee_id', $employee->id)
            ->where('status', 'absent')
            ->where('is_active', true)   // un pointage archivé ne retient plus d'absence sur la paie
            ->whereYear('attendance_date', substr($period, 0, 4))
            ->whereMonth('attendance_date', substr($period, 5, 2))
            ->count();

        // 🔴→✅ TICKET 14.38 — CALCUL DÉLÉGUÉ AU SERVICE DE PAIE.
        //
        // Le taux CNSS de 3,6 % était écrit en dur ici, et deux familles de
        // prélèvements manquaient entièrement : l'ITS (retenue salariale
        // progressive) et les charges patronales béninoises (VPS, CNSS
        // pensions, prestations familiales, risques professionnels). Le
        // bulletin sous-déclarait donc l'entreprise et surestimait le net.
        $calcul = app(PayrollCalculationService::class)->calculer($gross, $absenceDays);

        $absenceDeduction = $calcul['retenue_absence'];
        $cnssDeduction = $calcul['cnss_salariale'];
        $net = $calcul['net'];

        DB::transaction(function () use ($employee, $period, $gross, $calcul, $absenceDeduction, $cnssDeduction, $net) {
            $payslip = Payslip::create([
                'employee_id' => $employee->id,
                'period_month' => $period,
                'gross_salary' => $gross,
                'absence_deduction' => $absenceDeduction,
                'cnss_deduction' => $cnssDeduction,
                // Retenue salariale : diminue le net versé.
                'its_deduction' => $calcul['its'],
                // Charges patronales : payées EN PLUS, ne touchent pas le net.
                'vps_employer' => $calcul['vps'],
                'cnss_employer_pension' => $calcul['cnss_patronale_pension'],
                'cnss_employer_family' => $calcul['cnss_patronale_famille'],
                'cnss_employer_risk' => $calcul['cnss_patronale_risque'],
                'net_salary' => $net,
            ]);

            // Décrément réel de trésorerie à la validation — voir docblock.
            $account = TreasuryAccount::where('is_active', true)->first();
            if ($account) {
                $account->decrement('balance', $net);
            }

            // 🔴→✅ TICKET 14.25 — ÉCRITURE COMPTABLE ENFIN GÉNÉRÉE.
            // Dernier des trois flux financiers cites par le CDC (vente, achat,
            // paie) a n'en produire aucune. La charge portee au debit est le
            // salaire REELLEMENT DU (net + retenue CNSS), la retenue etant une
            // dette envers l'organisme et non une non-depense : comptabiliser
            // le seul net sous-estimerait les charges de personnel chaque mois.
            $ecriture = app(RecordPayrollAccountingEntryAction::class)
                ->execute($payslip, $account?->id);

            AuditLog::record('payslip.paid', 'rh');

            if ($ecriture === null) {
                // Jamais silencieux — meme discipline que le POS et les Achats.
                AuditLog::record('payslip.accounting_entry_missing', 'comptabilite');
                $this->dispatch('toast', message: "Règlement validé — ATTENTION : écriture comptable non générée (compte manquant au plan comptable). À régulariser au Journal Comptable.", type: 'warning');
            }
        });

        $this->dispatch('toast', message: "Règlement de {$employee->last_name} {$employee->first_name} validé.", type: 'success');
    }

    public function render()
    {
        return view('livewire.rh.gestion-paie');
    }
}
