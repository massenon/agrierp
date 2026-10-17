<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class TreasuryAccount extends Model
{
    use HasUuids;

    protected $fillable = [
        'type', 'label', 'account_code', 'bank_name', 'holder_name',
        'operator_name', 'rib', 'iban', 'phone_number', 'sim_serial', 'balance', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'balance' => 'decimal:2',
            'is_active' => 'boolean',
        ];
    }
}
