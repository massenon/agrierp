<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class CreditNote extends Model
{
    use HasUuids;

    protected $fillable = [
        'credit_note_number', 'sale_id', 'product_id', 'qty', 'amount',
        'reason', 'decision', 'inspection_notes', 'status', 'accounting_entry_id',
    ];

    protected function casts(): array
    {
        return [
            'qty' => 'decimal:2',
            'amount' => 'decimal:2',
        ];
    }

    public function sale()
    {
        return $this->belongsTo(Sale::class, 'sale_id');
    }

    public function product()
    {
        return $this->belongsTo(Product::class, 'product_id');
    }

    /** Ticket AV1 — l'année est celle de la DATE de l'avoir (un retour du poste daté de décembre reçu en janvier). */
    public static function generateCreditNoteNumber(?\DateTimeInterface $quand = null): string
    {
        $year = ($quand ? \Carbon\Carbon::instance($quand) : now())->format('Y');
        $prefix = "AV-{$year}-";

        $lastNumber = static::where('credit_note_number', 'like', $prefix.'%')
            ->selectRaw("MAX(CAST(SUBSTRING(credit_note_number, LENGTH(?) + 1) AS UNSIGNED)) as max_num", [$prefix])
            ->value('max_num');

        return $prefix.str_pad((int) $lastNumber + 1, 3, '0', STR_PAD_LEFT);
    }
}
