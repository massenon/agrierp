<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class PurchaseOrderLine extends Model
{
    use HasUuids;

    protected $fillable = ['purchase_order_id', 'product_id', 'qty', 'estimated_unit_price'];

    protected function casts(): array
    {
        return [
            'qty' => 'decimal:2',
            'estimated_unit_price' => 'decimal:2',
        ];
    }

    public function purchaseOrder()
    {
        return $this->belongsTo(PurchaseOrder::class, 'purchase_order_id');
    }

    public function product()
    {
        return $this->belongsTo(Product::class, 'product_id');
    }
}
