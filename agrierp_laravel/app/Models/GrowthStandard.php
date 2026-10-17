<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket 14.9 (Sprint 14) — objectif de GMQ (g/jour) par espèce et par stade.
 * Référentiel paramétrable, même forme que `FeedRationStandard`.
 */
class GrowthStandard extends Model
{
    use HasUuids;

    protected $fillable = ['species_code', 'stage_label', 'gmq_min_g_per_day', 'gmq_max_g_per_day'];
}
