<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class VeterinaryRecord extends Model
{
    use HasUuids;

    protected $fillable = [
        'lot_id', 'action_type', 'product_used', 'dose', 'vet_name',
        'symptomes', 'gravite', 'cost', 'record_date', 'daily_entry_id', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'cost' => 'decimal:2',
            'record_date' => 'date',
            'is_active' => 'boolean',
        ];
    }

    public function lot()
    {
        return $this->belongsTo(LivestockLot::class, 'lot_id');
    }
}
