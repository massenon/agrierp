<?php

namespace App\Livewire\RH;

use App\Models\AttendanceRecord;
use App\Models\AuditLog;
use App\Models\Employee;
use Illuminate\Validation\Rule;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * feuille-pointage.html → Livewire\RH\FeuillePointage
 * "Suivi quotidien des heures de présence du personnel et des
 * stagiaires."
 *
 * ⚠️ "et des stagiaires" (sous-titre du prototype) non honoré à la
 * lettre : `attendance_records.employee_id` référence uniquement
 * `employees` (schéma documenté, ticket 8.1) — aucune colonne
 * polymorphe ne permet d'y rattacher un stagiaire. Élargir la contrainte
 * pour accepter les deux types casserait l'intégrité référentielle du
 * schéma documenté ; le pointage des stagiaires reste hors périmètre de
 * cet écran (leurs absences sont déjà suivies séparément par
 * `internship_absences`, Registre Stagiaires).
 *
 * Contrainte réelle `unique(employee_id, attendance_date)` (ticket 8.1)
 * respectée : un employé ne peut avoir qu'un seul pointage par jour —
 * `updateOrCreate` plutôt que `create`, jamais un doublon silencieux.
 */
class FeuillePointage extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    public ?string $editingRecordId = null;

    public string $employeeId = '';

    public string $attendanceDate = '';

    public string $checkIn = '';

    public string $checkOut = '';

    public string $status = '';

    public function mount(): void
    {
        $this->attendanceDate = now()->format('Y-m-d');
    }

    public function getEmployeesProperty()
    {
        return Employee::where('is_active', true)->orderBy('last_name')->get();
    }

    public function getKpisProperty(): array
    {
        $today = AttendanceRecord::where('is_active', true)->whereDate('attendance_date', now())->get();

        return [
            'presents' => $today->whereIn('status', ['present', 'retard'])->count(),
            'absents' => $today->where('status', 'absent')->count(),
            'retards' => $today->where('status', 'retard')->count(),
        ];
    }

    public function getRecordsProperty()
    {
        $statusMap = ['Présent' => 'present', 'Absent' => 'absent', 'Retard' => 'retard', 'Congé' => 'conge'];

        return AttendanceRecord::with('employee')
            ->where('is_active', true)
            ->when($this->search, fn ($q) => $q->whereHas('employee', fn ($q2) => $q2->where('first_name', 'like', '%'.$this->search.'%')->orWhere('last_name', 'like', '%'.$this->search.'%')))
            ->when($this->statusFilter, fn ($q) => $q->where('status', $statusMap[$this->statusFilter] ?? $this->statusFilter))
            ->orderByDesc('attendance_date')
            ->limit(100)
            ->get();
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR COMPARAISON STRUCTURELLE RIGOUREUSE : le
     * bouton "Exporter PDF" était totalement absent — même schéma déjà
     * trouvé sur `RegistreEmployes`/`Devis`/`GestionStocks`/`ListeAchats`.
     */
    public function exportPointagePdf()
    {
        $this->authorize('view-rh');

        $records = $this->records;

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.feuille-pointage',
            ['records' => $records],
            'Feuille de Pointage',
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'feuille-pointage-'.now()->format('Y-m-d').'.pdf');
    }

    public function newRecord(): void
    {
        $this->reset(['editingRecordId', 'employeeId', 'checkIn', 'checkOut', 'status']);
        $this->attendanceDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-create-feuille-pointage');
    }

    public function editRecord(string $id): void
    {
        $record = AttendanceRecord::findOrFail($id);
        $this->editingRecordId = $record->id;
        $this->employeeId = $record->employee_id;
        $this->attendanceDate = $record->attendance_date->format('Y-m-d');
        $this->checkIn = $record->check_in ? substr($record->check_in, 0, 5) : '';
        $this->checkOut = $record->check_out ? substr($record->check_out, 0, 5) : '';
        $this->status = $record->status;
        $this->dispatch('open-modal', name: 'modal-create-feuille-pointage');
    }

    public function savePointage(): void
    {
        $this->validate([
            'employeeId' => ['required', 'exists:employees,id'],
            'attendanceDate' => ['required', 'date'],
            'checkIn' => ['nullable'],
            'checkOut' => ['nullable'],
            'status' => ['required', Rule::in(['present', 'absent', 'retard', 'conge'])],
        ]);

        $payload = [
            'check_in' => $this->checkIn ?: null,
            'check_out' => $this->checkOut ?: null,
            'status' => $this->status,
            'is_active' => true,
        ];

        // Unique(employee_id, attendance_date) respectée — jamais un doublon.
        AttendanceRecord::updateOrCreate(
            ['employee_id' => $this->employeeId, 'attendance_date' => $this->attendanceDate],
            $payload
        );

        AuditLog::record($this->editingRecordId ? 'attendance.updated' : 'attendance.created', 'rh');
        $this->dispatch('close-modal', name: 'modal-create-feuille-pointage');
        $this->dispatch('toast', message: 'Pointage enregistré avec succès.', type: 'success');
    }

    public function archiveRecord(string $id): void
    {
        AttendanceRecord::findOrFail($id)->update(['is_active' => false]);
        AuditLog::record('attendance.archived', 'rh');
        $this->dispatch('toast', message: 'Pointage archivé avec succès.', type: 'warning');
    }

    public function render()
    {
        return view('livewire.rh.feuille-pointage');
    }
}
