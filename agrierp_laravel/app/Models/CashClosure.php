<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Sprint C — Clôture de caisse.
 */
class CashClosure extends Model
{
    use HasUuids;

    protected $fillable = [
        'fiscal_year_id',
        'closure_date',
        'device_id',
        'ventes_especes',
        'ventes_mobile_money',
        'ventes_virement',
        'fond_de_caisse',
        'montant_compte',
        'ecart',
        'statut',
        'accounting_entry_id',
        'created_by',
    ];

    protected function casts(): array
    {
        return [
            'closure_date'       => 'date',
            'ventes_especes'     => 'decimal:2',
            'ventes_mobile_money'=> 'decimal:2',
            'ventes_virement'    => 'decimal:2',
            'fond_de_caisse'     => 'decimal:2',
            'montant_compte'     => 'decimal:2',
            'ecart'              => 'decimal:2',
        ];
    }

    public function fiscalYear()
    {
        return $this->belongsTo(FiscalYear::class);
    }

    public function accountingEntry()
    {
        return $this->belongsTo(AccountingEntry::class);
    }

    public function createdByUser()
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
