<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket 14.14 (Sprint 14) — clôture mensuelle légère.
 *
 * Un mois est VERROUILLÉ s'il porte une clôture non déclôturée. La méthode
 * `isPeriodLocked()` est le point de vérité unique de ce verrou : le Journal
 * Comptable s'en sert pour refuser toute écriture datée d'un mois clos.
 */
class PeriodicClosure extends Model
{
    use HasUuids;

    protected $fillable = ['period', 'closed_at', 'closed_by', 'reopened_at', 'reopened_by'];

    protected function casts(): array
    {
        return [
            'closed_at' => 'datetime',
            'reopened_at' => 'datetime',
        ];
    }

    public function closedBy()
    {
        return $this->belongsTo(User::class, 'closed_by');
    }

    public function reopenedBy()
    {
        return $this->belongsTo(User::class, 'reopened_by');
    }

    /** Le mois est-il actuellement verrouillé ? Une déclôture lève le verrou. */
    public function isLocked(): bool
    {
        return $this->reopened_at === null;
    }

    /**
     * Une écriture datée de `$date` tombe-t-elle dans un mois clôturé ?
     * Point de vérité unique — jamais réimplémenté ailleurs.
     */
    public static function isDateLocked(string $date): bool
    {
        $periode = \Carbon\Carbon::parse($date)->format('Y-m');

        return static::where('period', $periode)->whereNull('reopened_at')->exists();
    }
}
