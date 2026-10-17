<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Quote extends Model
{
    use HasUuids;

    protected $fillable = [
        'quote_number', 'customer_id', 'articles_description', 'amount',
        'tva_rate', 'validity_days', 'quote_date', 'note', 'status',
        'converted_sale_id', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'tva_rate' => 'decimal:2',
            'quote_date' => 'date',
            'is_active' => 'boolean',
        ];
    }

    public function customer()
    {
        return $this->belongsTo(Customer::class, 'customer_id');
    }

    public function getValidUntilAttribute(): \Illuminate\Support\Carbon
    {
        return $this->quote_date->copy()->addDays($this->validity_days);
    }

    public function getAmountTtcAttribute(): float
    {
        return round((float) $this->amount * (1 + (float) $this->tva_rate / 100), 2);
    }

    public static function generateQuoteNumber(): string
    {
        $year = now()->format('Y');
        $prefix = "DEV-{$year}-";

        $lastNumber = static::where('quote_number', 'like', $prefix.'%')
            ->selectRaw("MAX(CAST(SUBSTRING(quote_number, LENGTH(?) + 1) AS UNSIGNED)) as max_num", [$prefix])
            ->value('max_num');

        return $prefix.str_pad((int) $lastNumber + 1, 3, '0', STR_PAD_LEFT);
    }
}
