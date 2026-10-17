<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class FeedRationStandard extends Model
{
    use HasUuids;

    // ⚠️ TICKET 14.55 — `is_active` DOIT FIGURER ICI. Un champ absent de cette
    // liste est IGNORÉ EN SILENCE par une affectation de masse : l'archivage
    // aurait été appelé, aurait retourné vrai, et la ration serait restée
    // active. Le projet a déjà payé ce piège deux fois (statut MeCeF jamais
    // persisté, étape de clôture affichant « validée » sans rien enregistrer).
    protected $fillable = ['species_code', 'stage_label', 'ration_g_per_day', 'is_active'];

    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }
}
