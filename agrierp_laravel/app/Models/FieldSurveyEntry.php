<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket RELEVES-1 — une ligne de l'onglet « Relevés de terrain » (Paramètres Élevage). ⚠️ On n'écrit JAMAIS ce modèle
 * hors de `App\Services\Elevage\ReleveTerrainService` (point de passage unique : validation, statut, audit).
 */
class FieldSurveyEntry extends Model
{
    use HasUuids;

    protected $fillable = [
        'type', 'label', 'species_code', 'data', 'status', 'validated_by', 'validated_at',
        'device_id', 'sync_status', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'data' => 'array',
            'validated_at' => 'datetime',
            'is_active' => 'boolean',
        ];
    }

    public function validateur()
    {
        return $this->belongsTo(User::class, 'validated_by');
    }

    public function estAValider(): bool
    {
        return $this->status === 'a_valider';
    }
}
