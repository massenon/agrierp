<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket SW-1 — curseur de tirage d'un poste et drapeau « resynchronisation demandée » (`ResynchronisationPostesService`).
 * Propre au serveur : jamais tiré ni poussé.
 */
class PosteSynchronisation extends Model
{
    use HasUuids;

    protected $table = 'poste_synchronisations';

    public $timestamps = false;

    protected $fillable = [
        'poste', 'curseur_tirage', 'dernier_tirage_le', 'resync_demandee_le', 'resync_demandee_par', 'resync_acquittee_le',
    ];

    protected function casts(): array
    {
        return [
            'curseur_tirage' => 'datetime',
            'dernier_tirage_le' => 'datetime',
            'resync_demandee_le' => 'datetime',
            'resync_acquittee_le' => 'datetime',
        ];
    }
}
