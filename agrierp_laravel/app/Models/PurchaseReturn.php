<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class PurchaseReturn extends Model
{
    use HasUuids;

    // ⚠️ `id` reste généré par le serveur (une ligne de retour n'a pas d'identité côté poste) ; c'est
    // `return_batch_id`, fourni par le poste, qui identifie le RETOUR et rend un renvoi inoffensif (ticket 15.20).
    protected $fillable = [
        'purchase_id', 'product_id', 'qty', 'reason',
        'return_batch_id', 'purchase_line_id', 'return_date', 'device_id',
    ];

    protected function casts(): array
    {
        return ['qty' => 'decimal:2', 'return_date' => 'date'];
    }

    public function purchase()
    {
        return $this->belongsTo(Purchase::class, 'purchase_id');
    }

    public function product()
    {
        return $this->belongsTo(Product::class, 'product_id');
    }
}
