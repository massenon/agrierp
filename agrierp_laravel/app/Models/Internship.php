<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Internship extends Model
{
    use HasUuids;

    protected $fillable = ['first_name', 'last_name', 'school', 'start_date', 'end_date', 'monthly_fee', 'fee_paid', 'birth_date', 'birth_place', 'civilite'];

    protected function casts(): array
    {
        return [
            'start_date' => 'date',
            'end_date'   => 'date',
            'birth_date' => 'date',
            'monthly_fee' => 'decimal:2',
            'fee_paid' => 'boolean',
        ];
    }

    public function absences()
    {
        return $this->hasMany(InternshipAbsence::class, 'internship_id');
    }

    public function getFullNameAttribute(): string
    {
        return trim("{$this->first_name} {$this->last_name}");
    }

    public function getIsActiveAttribute(): bool
    {
        return ! $this->end_date || $this->end_date->isFuture();
    }
}
