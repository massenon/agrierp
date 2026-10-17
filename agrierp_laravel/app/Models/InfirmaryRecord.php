<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class InfirmaryRecord extends Model
{
    use HasUuids;

    protected $fillable = ['lot_id', 'sujet_ref', 'motif', 'isolation_level', 'entry_date', 'status'];

    protected function casts(): array
    {
        return ['entry_date' => 'date'];
    }

    public function lot()
    {
        return $this->belongsTo(LivestockLot::class, 'lot_id');
    }
}
