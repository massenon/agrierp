<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Remboursement fournisseur (ticket 15.20). L'`id` est celui du poste : il n'est pas remplissable, il est
 * assigné explicitement (`$model->id = …`), comme `SupplierPayment`.
 */
class SupplierRefund extends Model
{
    protected $keyType = 'string';

    public $incrementing = false;

    protected $fillable = [
        'supplier_id', 'treasury_account_id', 'amount', 'applied_amount', 'refund_date', 'device_id',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'applied_amount' => 'decimal:2',
            'refund_date' => 'date',
        ];
    }

    public function supplier()
    {
        return $this->belongsTo(Supplier::class, 'supplier_id');
    }
}
