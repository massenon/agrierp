<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class VeterinaryWithdrawalPeriod extends Model
{
    use HasUuids;

    protected $fillable = ['lot_id', 'product_used', 'start_date', 'withdrawal_days', 'end_date', 'triggered_by_daily_entry_id'];

    protected function casts(): array
    {
        return [
            'start_date' => 'date',
            'end_date' => 'date',
        ];
    }

    public function lot()
    {
        return $this->belongsTo(LivestockLot::class, 'lot_id');
    }

    public static function isLotBlocked(string $lotId): bool
    {
        return static::where('lot_id', $lotId)->where('end_date', '>=', now()->toDateString())->exists();
    }
}
