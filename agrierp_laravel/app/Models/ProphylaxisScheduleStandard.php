<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket 15.35 — `cycle_day_start`/`cycle_day_end` sont désormais assignables en masse.
 * Ils ne l'étaient pas : un `create()`/`updateOrCreate()` les ignorait SANS ERREUR et
 * l'entrée restait « calendaire » (bornes nulles), donc jamais évaluée par le moteur.
 * ⚠️ `ParametresElevage::saveProphy()` ne les renseigne toujours pas — voir README 15.35.
 */
class ProphylaxisScheduleStandard extends Model
{
    use HasUuids;

    protected $table = 'prophylaxis_schedule_standards';

    protected $fillable = [
        'species_code', 'period_label', 'cycle_day_start', 'cycle_day_end', 'treatment',
        'product_recommended', 'dosage', 'withdrawal_days', 'is_active',
    ];

    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }
}
