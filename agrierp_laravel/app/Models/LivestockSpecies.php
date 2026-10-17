<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class LivestockSpecies extends Model
{
    use HasUuids;

    protected $fillable = ['code', 'label', 'is_enabled', 'icon'];

    protected function casts(): array
    {
        return ['is_enabled' => 'boolean'];
    }

    public function products()
    {
        return $this->hasMany(Product::class, 'species_id');
    }

    /**
     * ⚠️ CORRECTION (Sprint 11, ticket Modules Actifs) : `is_enabled` sur
     * CE modèle n'est que la donnée de référence "l'espèce existe" —
     * `ModuleConfig::isEnabled()` (ticket 3.9) fait autorité pour savoir
     * si le module est réellement actif côté produit (voir docblock de
     * `ModuleConfig`). 5 composants du projet filtraient à tort sur
     * `livestock_species.is_enabled` directement — corrigés pour utiliser
     * ce scope, un seul point de vérité désormais partout.
     */
    public function scopeEnabled($query)
    {
        $enabledCodes = ModuleConfig::where('is_enabled', true)->pluck('species_code');

        return $query->whereIn('code', $enabledCodes);
    }
}
