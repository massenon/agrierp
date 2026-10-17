<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket 15.46 — transfert de sujets d'une bande à une autre, le même jour. Source de vérité des colonnes
 * `transfert_*` des fiches (voir `TransfertsEntreBandesService`). Jamais supprimé : annulé (`is_active = false`).
 */
class LivestockTransfer extends Model
{
    use HasUuids;

    protected $fillable = [
        'source_lot_id', 'target_lot_id', 'transfer_date', 'quantity', 'categorie',
        'constitution', 'motif', 'user_id', 'device_id', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'transfer_date' => 'date:Y-m-d',
            'quantity' => 'integer',
            'constitution' => 'boolean',
            'is_active' => 'boolean',
        ];
    }

    public function source()
    {
        return $this->belongsTo(LivestockLot::class, 'source_lot_id');
    }

    public function cible()
    {
        return $this->belongsTo(LivestockLot::class, 'target_lot_id');
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function scopeActifs($query)
    {
        return $query->where('is_active', true);
    }
}
