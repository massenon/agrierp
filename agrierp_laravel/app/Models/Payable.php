<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Payable extends Model
{
    use HasUuids;

    protected $fillable = ['supplier_id', 'purchase_id', 'expense_id', 'amount', 'amount_paid', 'due_date', 'status'];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'amount_paid' => 'decimal:2',
            'due_date' => 'date',
        ];
    }

    public function supplier()
    {
        return $this->belongsTo(Supplier::class, 'supplier_id');
    }

    public function purchase()
    {
        return $this->belongsTo(Purchase::class, 'purchase_id');
    }

    /** Ticket DEP7 — la dépense à crédit qui a ouvert cette dette (nul pour la dette d'un achat). */
    public function expense()
    {
        return $this->belongsTo(Expense::class, 'expense_id');
    }

    public function getBalanceAttribute(): float
    {
        return round((float) $this->amount - (float) $this->amount_paid, 2);
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
