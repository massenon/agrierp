<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class FiscalYear extends Model
{
    use HasUuids;

    /**
     * 🔴→✅ TICKET 14.28 — `step1_confirmed_at` ETAIT ABSENT DE CETTE LISTE.
     *
     * `ClotureExercice::confirmStep1()` fait pourtant
     * `$year->update(['step1_confirmed_at' => now()])` : l'affectation de masse
     * ecartait silencieusement la colonne. Le comptable cliquait « Marquer comme
     * termine », recevait le toast « Etape 1 validee », et RIEN n'etait
     * enregistre — l'etape redevenait non confirmee au rechargement suivant.
     * Defaut constate en executant reellement le parcours de cloture (14.28),
     * jamais visible en lecture de code puisque `update()` n'echoue pas.
     */
    protected $fillable = ['year', 'start_date', 'end_date', 'status', 'step1_confirmed_at', 'closed_at', 'closed_by'];

    protected function casts(): array
    {
        return [
            'start_date' => 'date',
            'end_date' => 'date',
            // Sans ce cast, la vue appelle `->format()` sur une CHAINE et
            // provoque une erreur fatale des que l'etape 1 est confirmee.
            'step1_confirmed_at' => 'datetime',
            'closed_at' => 'datetime',
        ];
    }

    public function closedByUser()
    {
        return $this->belongsTo(User::class, 'closed_by');
    }

    /** Exercice ouvert courant — un seul point de vérité pour cette notion, jamais recalculé ailleurs. */
    public static function current(): ?self
    {
        return static::where('status', 'ouvert')->orderByDesc('year')->first();
    }
}
