<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket S-T6 — un poste a demandé les comptes du serveur pour son contrôle de cohérence
 * (`CoherenceSynchronisationService`). Propre au serveur ; le résultat de la comparaison reste au poste.
 */
class ControleCoherence extends Model
{
    use HasUuids;

    protected $table = 'controles_coherence';

    public const UPDATED_AT = null;

    protected $fillable = ['user_id', 'poste', 'depuis'];

    protected function casts(): array
    {
        return [
            'depuis' => 'date',
            'created_at' => 'datetime',
        ];
    }
}
