<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket 14.8 (Sprint 14) — ligne d'un relevé bancaire importé, confrontée au
 * Grand Livre par `BankReconciliationService`.
 *
 * `amount` est SIGNÉ (positif = encaissement, négatif = décaissement), pour
 * pouvoir être comparé directement au solde signé d'une ligne d'écriture
 * (`debit − credit`) sans réinterprétation à chaque comparaison.
 *
 * Cast `statement_date` en `date:Y-m-d` — même précaution que
 * `LivestockDailyEntry` (ticket 14.4) : le cast `date` nu sérialise en
 * `Y-m-d H:i:s` et fait échouer toute comparaison de date en chaîne selon le
 * pilote.
 */
class BankStatementLine extends Model
{
    use HasUuids;

    protected $fillable = [
        'account_id', 'statement_date', 'label', 'amount',
        'is_reconciled', 'matched_entry_line_id',
    ];

    protected function casts(): array
    {
        return [
            'statement_date' => 'date:Y-m-d',
            'amount' => 'decimal:2',
            'is_reconciled' => 'boolean',
        ];
    }

    public function account()
    {
        return $this->belongsTo(ChartOfAccount::class, 'account_id');
    }
}
