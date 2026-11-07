<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket IMPORT-1 — une présentation de fichier à l'importation en masse (journal d'import du serveur).
 *
 * Statuts : `apercu` (lu et validé, rien d'écrit), `termine` (confirmé et écrit), `annule`.
 */
class ImportBatch extends Model
{
    use HasUuids;

    public const APERCU = 'apercu';

    public const TERMINE = 'termine';

    public const ANNULE = 'annule';

    protected $fillable = [
        'user_id', 'module', 'version_modele', 'nom_fichier', 'empreinte', 'statut',
        'lues', 'valides', 'ignorees', 'refusees', 'creees', 'avertissement', 'lignes', 'rapport', 'termine_le',
    ];

    protected function casts(): array
    {
        return [
            'lignes' => 'array',
            'rapport' => 'array',
            'termine_le' => 'datetime',
        ];
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
