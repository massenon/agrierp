<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class FeedType extends Model
{
    use HasUuids;

    protected $fillable = ['name', 'species_id', 'standard_bag_weight_kg', 'price_per_kg', 'is_active'];

    protected function casts(): array
    {
        return [
            'standard_bag_weight_kg' => 'decimal:2',
            'price_per_kg' => 'decimal:2',
            'is_active' => 'boolean',
        ];
    }

    public function species()
    {
        return $this->belongsTo(LivestockSpecies::class, 'species_id');
    }
}
