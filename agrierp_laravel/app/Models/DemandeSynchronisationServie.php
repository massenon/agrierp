<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket S-T6 — une demande de synchronisation SERVIE à un poste : la lecture par `GET /api/sync/demande` l'a marquée,
 * elle ne lui sera plus rendue. Propre au serveur.
 */
class DemandeSynchronisationServie extends Model
{
    use HasUuids;

    protected $table = 'demandes_synchronisation_servies';

    public $timestamps = false;

    protected $fillable = ['demande_id', 'poste', 'servie_le'];

    protected function casts(): array
    {
        return [
            'servie_le' => 'datetime',
        ];
    }

    public function demande()
    {
        return $this->belongsTo(DemandeSynchronisation::class, 'demande_id');
    }
}
