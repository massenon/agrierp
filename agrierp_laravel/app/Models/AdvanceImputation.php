<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Imputation d'une avance client sur une créance (ticket 15.19). L'`id` est celui du poste
 * quand l'imputation en vient : il n'est pas remplissable, il est assigné explicitement.
 */
class AdvanceImputation extends Model
{
    protected $keyType = 'string';

    public $incrementing = false;

    protected $fillable = [
        'customer_advance_id', 'receivable_id', 'amount', 'applied_amount', 'imputation_date', 'device_id',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'applied_amount' => 'decimal:2',
            'imputation_date' => 'date',
        ];
    }

    public function advance()
    {
        return $this->belongsTo(CustomerAdvance::class, 'customer_advance_id');
    }

    public function receivable()
    {
        return $this->belongsTo(Receivable::class, 'receivable_id');
    }
}
