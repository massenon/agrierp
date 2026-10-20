<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket S-T6 — demande de synchronisation déposée au web pour un poste (`poste`) ou pour tous (`poste` nul), lue par
 * les postes toutes les 30 s (`DemandeSynchronisationService`). Propre au serveur.
 */
class DemandeSynchronisation extends Model
{
    use HasUuids;

    protected $table = 'demandes_synchronisation';

    public $timestamps = false;

    protected $fillable = ['poste', 'demandee_le', 'demandee_par'];

    protected function casts(): array
    {
        return [
            'demandee_le' => 'datetime',
        ];
    }

    public function auteur()
    {
        return $this->belongsTo(User::class, 'demandee_par');
    }

    public function servies()
    {
        return $this->hasMany(DemandeSynchronisationServie::class, 'demande_id');
    }
}
