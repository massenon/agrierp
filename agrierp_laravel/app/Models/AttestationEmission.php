<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Une attestation fabriquée au poste (ATT-3) : son identifiant (celui du poste), son type, son NUMÉRO figé et l'instant
 * de l'émission. Voir la migration `create_attestation_emissions_table`.
 */
class AttestationEmission extends Model
{
    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = ['id', 'type', 'numero', 'issued_at', 'user_id'];

    protected function casts(): array
    {
        return ['issued_at' => 'datetime'];
    }
}
