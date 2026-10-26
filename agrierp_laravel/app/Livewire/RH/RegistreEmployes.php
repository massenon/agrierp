<?php

namespace App\Livewire\RH;

use App\Models\AuditLog;
use App\Models\Employee;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 8.2 (Sprint 8) — registre-employes.html → Livewire\RH\RegistreEmployes
 * "Répertoire du personnel permanent de la ferme."
 *
 * ⚠️ "Nom complet" (un seul champ dans le prototype, ex. "ADJOVI
 * Bernadin") scindé en Prénom/Nom pour respecter le schéma réel
 * (`employees.first_name`/`last_name`, ticket 8.1) — jamais un seul champ
 * texte libre stocké tel quel dans deux colonnes distinctes.
 *
 * Export PDF différé (PdfExportService à câbler dans une session dédiée,
 * même raison que dans les tickets précédents).
 */
class RegistreEmployes extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    public ?string $editingEmployeeId = null;

    public string $firstName = '';

    public string $lastName = '';

    public string $position = '';

    public string $hireDate = '';

    public ?float $baseSalary = null;

    public string $status = 'actif';

    public function mount(): void
    {
        $this->hireDate = now()->format('Y-m-d');
    }

    public function getKpisProperty(): array
    {
        return [
            'employes_actifs' => Employee::where('is_active', true)->count(),
            'nouveaux_annee' => Employee::where('is_active', true)->whereYear('hire_date', now()->year)->count(),
        ];
    }

    public function getEmployeesProperty()
    {
        $statusMap = ['Actif' => 'actif', 'Congé' => 'conge', 'Suspendu' => 'suspendu'];

        return Employee::where('is_active', true)
            ->when($this->search, fn ($q) => $q->where(fn ($q2) => $q2->where('first_name', 'like', '%'.$this->search.'%')->orWhere('last_name', 'like', '%'.$this->search.'%')))
            ->when($this->statusFilter, fn ($q) => $q->where('status', $statusMap[$this->statusFilter] ?? $this->statusFilter))
            ->orderBy('last_name')
            ->get();
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR COMPARAISON STRUCTURELLE RIGOUREUSE : le
     * bouton "Exporter PDF" était totalement absent — même schéma déjà
     * trouvé sur `Devis`/`GestionStocks`/`ListeAchats`. Réutilise
     * `PdfExportService`.
     */
    public function exportEmployesPdf()
    {
        $this->authorize('view-rh');

        $employees = $this->employees;

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.registre-employes',
            ['employees' => $employees],
            'Registre des Employés',
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'registre-employes-'.now()->format('Y-m-d').'.pdf');
    }

    public function newEmployee(): void
    {
        $this->reset(['editingEmployeeId', 'firstName', 'lastName', 'position', 'baseSalary']);
        $this->status = 'actif';
        $this->hireDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-create-registre-employes');
    }

    public function editEmployee(string $id): void
    {
        $employee = Employee::findOrFail($id);
        $this->editingEmployeeId = $employee->id;
        $this->firstName = $employee->first_name;
        $this->lastName = $employee->last_name;
        $this->position = (string) $employee->position;
        $this->hireDate = $employee->hire_date?->format('Y-m-d') ?? now()->format('Y-m-d');
        $this->baseSalary = $employee->base_salary ? (float) $employee->base_salary : null;
        $this->status = $employee->status;
        $this->dispatch('open-modal', name: 'modal-create-registre-employes');
    }

    public function saveEmployee(): void
    {
        $this->authorize('manage-rh');
        $this->validate([
            'firstName' => ['required', 'string', 'max:100'],
            'lastName' => ['required', 'string', 'max:100'],
            'position' => ['required', 'string'],
            'hireDate' => ['required', 'date'],
            'baseSalary' => ['nullable', 'numeric', 'min:0'],
            'status' => ['required', 'in:actif,conge,suspendu'],
        ]);

        $payload = [
            'first_name' => $this->firstName,
            'last_name' => $this->lastName,
            'position' => $this->position,
            'hire_date' => $this->hireDate,
            'base_salary' => $this->baseSalary,
            'status' => $this->status,
        ];

        if ($this->editingEmployeeId) {
            Employee::findOrFail($this->editingEmployeeId)->update($payload);
            AuditLog::record('employee.updated', 'rh');
            $message = 'Modification enregistrée avec succès.';
        } else {
            $payload['is_active'] = true;
            Employee::create($payload);
            AuditLog::record('employee.created', 'rh');
            $message = 'Enregistrement effectué avec succès.';
        }

        $this->dispatch('close-modal', name: 'modal-create-registre-employes');
        $this->dispatch('toast', message: $message, type: 'success');
    }

    public function archiveEmployee(string $id): void
    {
        $this->authorize('manage-rh');
        $employe = Employee::findOrFail($id);
        $employe->update(['is_active' => false]);
        AuditLog::record('employee.archived', 'rh', null, $employe);
        $this->dispatch('toast', message: 'Employé archivé avec succès.', type: 'warning');
    }

    public function render()
    {
        return view('livewire.rh.registre-employes');
    }
}
