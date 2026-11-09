<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Encaissement de créance reçu d'un poste (ticket VC-1). L'`id` est celui du poste : il n'est pas remplissable, il est
 * assigné explicitement.
 */
class ReceivablePayment extends Model
{
    protected $keyType = 'string';

    public $incrementing = false;

    protected $fillable = [
        'customer_id', 'receivable_id', 'treasury_account_id', 'amount', 'applied_amount', 'payment_date', 'device_id',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'applied_amount' => 'decimal:2',
            'payment_date' => 'date',
        ];
    }
}
