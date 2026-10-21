<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket ARC1 — une restauration ou une suppression définitive de la Corbeille (journal ; voir la migration).
 *
 * `id` n'est pas assignable en masse : il est posé explicitement (UUID de la demande née sur un poste), sinon généré.
 */
class CorbeilleOperation extends Model
{
    use HasUuids;

    protected $fillable = ['user_id', 'action', 'type', 'element_id', 'titre', 'issue', 'motif', 'device_id'];
}
