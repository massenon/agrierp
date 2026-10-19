<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket H3 — une ligne par tirage ou envoi d'un poste (`JournalSynchronisationService`). Propre au serveur.
 */
class JournalSynchronisation extends Model
{
    use HasUuids;

    protected $table = 'journal_synchronisation';

    public const UPDATED_AT = null;

    protected $fillable = ['user_id', 'poste', 'sens', 'nb_recus', 'nb_acceptes', 'nb_refuses'];

    protected function casts(): array
    {
        return [
            'nb_recus' => 'integer',
            'nb_acceptes' => 'integer',
            'nb_refuses' => 'integer',
            'created_at' => 'datetime',
        ];
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
