<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class LivestockReproductionEvent extends Model
{
    use HasUuids;

    protected $fillable = [
        'lot_id', 'mother_ref', 'sire_ref', 'saillie_date', 'palpation_date',
        'mise_bas_date_expected', 'mise_bas_date_actual', 'sevrage_date_expected',
        'nes_vivants', 'nes_morts', 'status',
    ];

    protected function casts(): array
    {
        return [
            'saillie_date' => 'date',
            'palpation_date' => 'date',
            'mise_bas_date_expected' => 'date',
            'mise_bas_date_actual' => 'date',
            'sevrage_date_expected' => 'date',
        ];
    }

    public function lot()
    {
        return $this->belongsTo(LivestockLot::class, 'lot_id');
    }
}
