<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class CostCenter extends Model
{
    use HasUuids;

    /**
     * Ticket DEP6 (DEP-Q1) — le centre de coût est OBLIGATOIRE à la saisie d'une dépense. Ce centre « Général » reçoit :
     * les dépenses d'avant la règle (migration) et celles d'un poste ANCIEN qui n'en envoie pas. Il n'existait AUCUN centre
     * « Général / Commun » avant : il est créé par la migration DEP6 et par le semoir.
     */
    public const LIBELLE_GENERAL = 'Général';

    protected $fillable = ['label', 'type', 'parent_species_id', 'is_active'];

    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }

    public function species()
    {
        return $this->belongsTo(LivestockSpecies::class, 'parent_species_id');
    }

    /** Le centre par défaut (« Général », filière), créé s'il manque ; jamais de doublon. */
    public static function general(): self
    {
        return self::firstOrCreate(
            ['label' => self::LIBELLE_GENERAL, 'type' => 'filiere'],
            ['is_active' => true],
        );
    }
}
