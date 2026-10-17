<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Transformation extends Model
{
    use HasUuids;

    protected $fillable = [
        'lot_id', 'product_id', 'qty_animals', 'qty_produced',
        'operator_id', 'transformation_date', 'accounting_entry_id',
    ];

    protected function casts(): array
    {
        return [
            'qty_produced' => 'decimal:2',
            'transformation_date' => 'date',
        ];
    }

    public function lot()
    {
        return $this->belongsTo(LivestockLot::class, 'lot_id');
    }

    public function product()
    {
        return $this->belongsTo(Product::class, 'product_id');
    }

    public function operator()
    {
        return $this->belongsTo(User::class, 'operator_id');
    }
}
