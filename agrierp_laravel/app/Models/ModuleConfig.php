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

    /**
     * UN SEUL POINT D'ÉCRITURE de l'activation d'un module (ticket MOD1) : l'écran web
     * (`ModulesActifs::toggleModule()`) et l'envoi du poste (`RecordModulesConfigFromDeviceAction`) passent ici,
     * avec le même journal d'audit. La valeur est EXPLICITE : rejouer un envoi ne rebascule jamais le module.
     * Ne touche que `modules_config` — jamais la comptabilité ni les données déjà saisies de l'espèce.
     */
    public static function definir(string $speciesCode, bool $actif, ?string $userId): self
    {
        $config = static::firstOrCreate(['species_code' => $speciesCode], ['is_enabled' => false]);
        $config->update(['is_enabled' => $actif, 'updated_by' => $userId]);

        AuditLog::record('module.toggled', 'parametres', $userId);

        return $config;
    }
}
