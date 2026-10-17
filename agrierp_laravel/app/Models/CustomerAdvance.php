<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class CustomerAdvance extends Model
{
    use HasUuids;

    // ⚠️ `id` n'est PAS remplissable : une avance reçue d'un poste porte l'UUID du poste, posé
    // explicitement (`$model->id = …`), jamais par affectation de masse (ticket 15.19).
    protected $fillable = [
        'customer_id', 'treasury_account_id', 'amount', 'amount_used', 'advance_date',
        'payment_mode', 'motif', 'device_id', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'amount_used' => 'decimal:2',
            'advance_date' => 'date',
            'is_active' => 'boolean',
        ];
    }

    public function customer()
    {
        return $this->belongsTo(Customer::class, 'customer_id');
    }

    public function treasuryAccount()
    {
        return $this->belongsTo(TreasuryAccount::class, 'treasury_account_id');
    }

    public function imputations()
    {
        return $this->hasMany(AdvanceImputation::class, 'customer_advance_id');
    }

    /**
     * Avance dont l'argent est entré en trésorerie ET au grand livre (D2). Les avances
     * saisies avant le ticket 15.19 n'ont ni l'un ni l'autre : elles restent « non comptabilisées ».
     */
    public function estComptabilisee(): bool
    {
        return $this->treasury_account_id !== null;
    }

    /** Avance déjà entamée (D4) : une part, même infime, a été imputée. */
    public function estEntamee(): bool
    {
        return (float) $this->amount_used > 0;
    }

    public function getRemainingAttribute(): float
    {
        return round((float) $this->amount - (float) $this->amount_used, 2);
    }
}
