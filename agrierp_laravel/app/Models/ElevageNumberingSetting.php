<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Table singleton — une seule ligne. `current()` la crée avec les valeurs
 * par défaut du prototype si elle n'existe pas encore (premier accès).
 */
class ElevageNumberingSetting extends Model
{
    use HasUuids;

    protected $table = 'elevage_numbering_settings';

    protected $fillable = [
        'bande_format', 'lapine_prefix', 'male_prefix', 'truie_prefix',
        'verrat_prefix', 'portee_prefix', 'volaille_prefix', 'parc_prefix', 'escargot_prefix',
    ];

    /**
     * ⚠️⚠️ LA RELECTURE N'EST PAS UNE PRÉCAUTION DÉCORATIVE. Les valeurs par
     * défaut (« BANDE B », « R », « T »…) vivent dans la MIGRATION, pas dans
     * le modèle : une ligne fraîchement insérée par `firstOrCreate([])` ne les
     * porte donc PAS en mémoire — tous ses attributs valent `null` tant qu'on
     * ne l'a pas relue.
     *
     * Le défaut ne se voyait pas ici, où la ligne existe depuis longtemps. Il
     * serait apparu sur une INSTALLATION NEUVE : le premier tirage aurait servi
     * neuf préfixes nuls au poste, qui aurait affiché « — » partout, et
     * l'éleveur aurait nommé ses cages à sa façon. Trouvé au ticket 14.77 par
     * un test qui part d'une base vide.
     */
    public static function current(): self
    {
        $reglage = static::query()->firstOrCreate([]);

        return $reglage->wasRecentlyCreated ? $reglage->refresh() : $reglage;
    }
}
