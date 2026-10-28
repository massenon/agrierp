<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Ticket CP-4 — une demande de clôture du poste, déjà jouée par le serveur (journal d'idempotence, voir la migration).
 * L'identifiant est l'UUID posé par le poste : il n'est donc pas généré ici.
 */
class FiscalClosureRequest extends Model
{
    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = ['id', 'kind', 'payload', 'user_id', 'handled_at'];

    protected function casts(): array
    {
        return ['payload' => 'array', 'handled_at' => 'datetime'];
    }
}
