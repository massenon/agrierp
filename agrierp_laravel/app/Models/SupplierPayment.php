<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Règlement fournisseur reçu d'un poste (ticket 15.16). L'`id` est celui du poste :
 * il n'est pas remplissable, il est assigné explicitement.
 */
class SupplierPayment extends Model
{
    protected $keyType = 'string';

    public $incrementing = false;

    protected $fillable = [
        'supplier_id', 'treasury_account_id', 'amount', 'applied_amount', 'payment_date', 'device_id',
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
