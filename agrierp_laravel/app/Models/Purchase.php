<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Purchase extends Model
{
    use HasUuids;

    protected $fillable = [
        'supplier_id', 'purchase_order_id', 'payment_mode', 'total',
        'accounting_entry_id', 'purchase_date', 'receipt_path',
    ];

    // ⚠️ `returned_at` et `supplier_credit` ne sont PAS remplissables : seul `PurchaseReturnService` les pose
    // (ticket 15.20). Écrire ces colonnes ailleurs contournerait la contre-passation.
    protected function casts(): array
    {
        return [
            'total' => 'decimal:2',
            'purchase_date' => 'date',
            'returned_at' => 'datetime',
            'supplier_credit' => 'decimal:2',
        ];
    }

    public function returns()
    {
        return $this->hasMany(PurchaseReturn::class, 'purchase_id');
    }

    public function estRetourne(): bool
    {
        return $this->returned_at !== null;
    }

    public function supplier()
    {
        return $this->belongsTo(Supplier::class, 'supplier_id');
    }

    public function purchaseOrder()
    {
        return $this->belongsTo(PurchaseOrder::class, 'purchase_order_id');
    }

    public function lines()
    {
        return $this->hasMany(PurchaseLine::class, 'purchase_id');
    }

    public function payable()
    {
        return $this->hasOne(Payable::class, 'purchase_id');
    }
}
