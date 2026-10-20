<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket S-T5 — l'identifiant `id_poste` d'un client, d'un fournisseur ou d'un produit créé au poste désigne la fiche
 * `id_serveur`, qui existait déjà (même clé naturelle). Écrite et lue par `FusionReferentielsService` seul.
 */
class CorrespondanceIdentifiant extends Model
{
    use HasUuids;

    protected $table = 'correspondances_identifiants';

    public $timestamps = false;

    protected $fillable = ['table_referentiel', 'id_poste', 'id_serveur', 'cle_naturelle', 'poste', 'user_id', 'fusionne_le'];

    protected function casts(): array
    {
        return [
            'fusionne_le' => 'datetime',
        ];
    }
}
