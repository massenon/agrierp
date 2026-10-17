<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket 14.38 (Sprint 14) — tranche du bareme IR-PTS / ITS (Benin).
 *
 * `to_amount` a null designe la tranche superieure, sans plafond.
 */
class IncomeTaxBracket extends Model
{
    use HasUuids;

    protected $fillable = ['from_amount', 'to_amount', 'rate', 'is_active'];

    protected function casts(): array
    {
        return [
            'from_amount' => 'decimal:2',
            'to_amount' => 'decimal:2',
            'rate' => 'decimal:2',
            'is_active' => 'boolean',
        ];
    }
}
