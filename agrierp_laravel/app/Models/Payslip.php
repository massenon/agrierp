<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Payslip extends Model
{
    use HasUuids;

    protected $fillable = [
        'employee_id', 'period_month', 'gross_salary', 'absence_deduction',
        'cnss_deduction', 'net_salary', 'accounting_entry_id',
        // Ticket 14.38 — retenue salariale ITS et charges patronales beninoises.
        'its_deduction', 'vps_employer', 'cnss_employer_pension',
        'cnss_employer_family', 'cnss_employer_risk',
    ];

    protected function casts(): array
    {
        return [
            'period_month' => 'date',
            'gross_salary' => 'decimal:2',
            'absence_deduction' => 'decimal:2',
            'cnss_deduction' => 'decimal:2',
            'net_salary' => 'decimal:2',
        ];
    }

    public function employee()
    {
        return $this->belongsTo(Employee::class, 'employee_id');
    }
}
