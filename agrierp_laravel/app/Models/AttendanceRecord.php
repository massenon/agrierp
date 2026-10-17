<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class AttendanceRecord extends Model
{
    use HasUuids;

    protected $fillable = ['employee_id', 'attendance_date', 'check_in', 'check_out', 'status', 'is_active'];

    protected function casts(): array
    {
        return [
            'attendance_date' => 'date',
            'is_active' => 'boolean',
        ];
    }

    public function employee()
    {
        return $this->belongsTo(Employee::class, 'employee_id');
    }
}
