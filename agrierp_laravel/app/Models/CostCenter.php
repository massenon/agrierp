<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class CostCenter extends Model
{
    use HasUuids;

    protected $fillable = ['label', 'type', 'parent_species_id', 'is_active'];

    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }

    public function species()
    {
        return $this->belongsTo(LivestockSpecies::class, 'parent_species_id');
    }
}
