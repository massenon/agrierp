<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class PurchaseOrder extends Model
{
    use HasUuids;

    protected $fillable = ['supplier_id', 'expected_delivery_date', 'status'];

    protected function casts(): array
    {
        return ['expected_delivery_date' => 'date'];
    }

    public function supplier()
    {
        return $this->belongsTo(Supplier::class, 'supplier_id');
    }

    public function lines()
    {
        return $this->hasMany(PurchaseOrderLine::class, 'purchase_order_id');
    }

    public function purchase()
    {
        return $this->hasOne(Purchase::class, 'purchase_order_id');
    }
}
