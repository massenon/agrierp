<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Receivable extends Model
{
    use HasUuids;

    protected $fillable = ['customer_id', 'sale_id', 'amount', 'amount_paid', 'due_date', 'status'];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'amount_paid' => 'decimal:2',
            'due_date' => 'date',
        ];
    }

    public function customer()
    {
        return $this->belongsTo(Customer::class, 'customer_id');
    }

    public function sale()
    {
        return $this->belongsTo(Sale::class, 'sale_id');
    }

    public function reminders()
    {
        return $this->hasMany(CustomerReminder::class, 'receivable_id');
    }

    public function getBalanceAttribute(): float
    {
        return round((float) $this->amount - (float) $this->amount_paid, 2);
    }

    public function getDaysOverdueAttribute(): int
    {
        if (! $this->due_date || $this->status === 'soldee') {
            return 0;
        }

        return max(0, now()->diffInDays($this->due_date, false) * -1);
    }

    public function getDisplayStatusAttribute(): string
    {
        if ($this->balance <= 0) {
            return 'soldee';
        }

        if ($this->due_date && $this->due_date->isPast()) {
            return 'en_retard';
        }

        return 'en_cours';
    }
}
