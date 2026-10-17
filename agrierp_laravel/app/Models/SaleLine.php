<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * `manual_total_amount` = source de vérité (Document 01 §6.7). `unit_price`
 * n'est dérivé QUE pour l'affichage — voir `App\Actions\RecordPosSaleAction`.
 */
class SaleLine extends Model
{
    use HasUuids;

    protected $fillable = [
        'sale_id', 'product_id', 'qty', 'unit_price',
        'manual_total_amount', 'is_manual_price', 'cost_center_id',
        // Ticket 14.44 — bande d'origine du sujet vendu. Nulle pour tout
        // produit sans espèce (provende, œufs, intrants).
        'lot_id',
    ];

    protected function casts(): array
    {
        return [
            'qty' => 'decimal:2',
            'unit_price' => 'decimal:2',
            'manual_total_amount' => 'decimal:2',
            'is_manual_price' => 'boolean',
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

    public function lot()
    {
        return $this->belongsTo(LivestockLot::class, 'lot_id');
    }
}
