<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Source de vérité UNIQUE et faisant autorité pour l'activation d'un
 * module espèce (ticket 3.9) — `livestock_species.is_enabled` (ticket 2.1)
 * reste la donnée de référence "espèce existe dans le référentiel", mais
 * `modules_config.is_enabled` est LE bascule réel côté produit (avec
 * traçabilité `updated_by`, piloté depuis Paramètres > Modules Actifs,
 * Sprint 11). `ModuleConfig::isEnabled()` fait autorité pour toute
 * visibilité conditionnelle (sidebar, hub, route).
 */
class ModuleConfig extends Model
{
    use HasUuids;

    protected $table = 'modules_config';

    protected $fillable = ['species_code', 'is_enabled', 'updated_by'];

    protected function casts(): array
    {
        return ['is_enabled' => 'boolean'];
    }

    public static function isEnabled(string $speciesCode): bool
    {
        return (bool) static::where('species_code', $speciesCode)->value('is_enabled');
    }
}
